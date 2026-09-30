import { http } from '@kit.NetworkKit';
import { ApiConfig } from './ApiConfig';
import { ApiError } from './ApiError';
import { buffer } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export interface MultipartUploadFile {
  fieldName: string;
  uri: string;
  fileName: string;
  contentType: string;
}

interface NativeErrorDetail {
  code?: number | string;
  message?: string;
}

export class HttpClient {
  private static instance: HttpClient | null = null;
  private tokenManager: TokenManager;

  private constructor() {
    this.tokenManager = TokenManager.getInstance();
  }

  static getInstance(): HttpClient {
    if (!HttpClient.instance) {
      HttpClient.instance = new HttpClient();
    }
    return HttpClient.instance;
  }

  private buildHeaders(contentType?: string): Record<string, string> {
    const headers: Record<string, string> = {};
    const token = this.tokenManager.getToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    if (contentType) {
      headers['Content-Type'] = contentType;
    }
    return headers;
  }

  private async emulatorUploadBridgeReady(): Promise<boolean> {
    const probe = http.createHttp();
    try {
      const response = await probe.request('http://10.0.2.2:18766/healthz', {
        method: http.RequestMethod.GET,
        connectTimeout: 3000,
        readTimeout: 3000,
      });
      return response.responseCode === 200 &&
        (response.result as string).includes('btir-emulator-upload-bridge');
    } catch (error) {
      return false;
    } finally {
      probe.destroy();
    }
  }

  async request<T>(method: string, path: string, body?: Object, contentType?: string): Promise<T> {
    const baseUrl = ApiConfig.getInstance().baseUrl;
    const url = `${baseUrl}${path}`;
    const headers = this.buildHeaders(contentType);

    let requestBody: string | undefined = undefined;
    if (body !== undefined) {
      requestBody = JSON.stringify(body);
    }

    try {
      const httpRequest = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: method as http.RequestMethod,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
      };
      if (requestBody) {
        options.extraData = requestBody;
      }

      const response = await httpRequest.request(url, options);
      httpRequest.destroy();

      const status = response.responseCode;

      if (status === 204) {
        return undefined as T;
      }

      const responseText = response.result as string;
      let responseData: Object | string = responseText;
      try {
        responseData = JSON.parse(responseText);
      } catch (e) {
        // 非 JSON 响应
      }

      if (status >= 400) {
        throw new ApiError(status, responseData);
      }

      return responseData as T;
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError(0, String(error), `网络请求失败: ${String(error)}`);
    }
  }

  async get<T>(path: string): Promise<T> {
    return this.request<T>('GET', path);
  }

  async post<T>(path: string, body?: Object, contentType?: string): Promise<T> {
    return this.request<T>('POST', path, body, contentType ?? 'application/json');
  }

  async delete<T>(path: string): Promise<T> {
    return this.request<T>('DELETE', path);
  }

  async patch<T>(path: string, body: Object): Promise<T> {
    return this.request<T>('PATCH', path, body, 'application/json');
  }

  async uploadFiles<T>(path: string, files: MultipartUploadFile[], cacheDir: string,
    extraFields?: Record<string, string>, onStage?: (stage: string) => void): Promise<T> {
    const baseUrl = ApiConfig.getInstance().baseUrl;
    let url = `${baseUrl}${path}`;
    const headers = this.buildHeaders();
    const temporaryPaths: string[] = [];
    let httpRequest: http.HttpRequest | null = null;
    let preparingFiles: boolean = true;
    let uploadedBytes: number = 0;
    let uploadTotalBytes: number = 0;
    let lastProgressPercent: number = -1;
    let bodyBytes: number = 0;

    try {
      const formData: http.MultiFormData[] = [];
      for (let index = 0; index < files.length; index++) {
        const file = files[index];
        onStage?.(`正在准备文件 ${index + 1}/${files.length}…`);
        const safeName = file.fileName.replace(/[^a-zA-Z0-9._-]/g, '_');
        const temporaryPath = `${cacheDir}/btir-upload-${Date.now()}-${index}-${safeName}`;
        const source = await fs.open(file.uri, fs.OpenMode.READ_ONLY);
        try {
          temporaryPaths.push(temporaryPath);
          await fs.copyFile(source.fd, temporaryPath);
        } finally {
          await fs.close(source);
        }
        bodyBytes += (await fs.stat(temporaryPath)).size;
        formData.push({
          name: file.fieldName,
          contentType: file.contentType,
          remoteFileName: file.fileName,
          filePath: temporaryPath,
        });
      }
      if (extraFields) {
        for (const key of Object.keys(extraFields)) {
          formData.push({ name: key, contentType: 'text/plain', data: extraFields[key] });
        }
      }

      // 正式服务的代理对整个 multipart 请求限制为 512 MiB，预留表单头部空间。
      if (bodyBytes + 64 * 1024 >= 512 * 1024 * 1024) {
        throw new ApiError(413, '文件过大', '文件总大小已接近服务器 512 MiB 上传上限，请压缩或拆分后重试');
      }

      let viaBridge = false;
      if (deviceInfo.productModel.toLowerCase() === 'emulator' &&
        baseUrl === 'https://btir-online.ai-premol.cn') {
        onStage?.('正在检查模拟器上传服务…');
        if (!(await this.emulatorUploadBridgeReady())) {
          throw new ApiError(0, '模拟器上传服务不可用',
            '请在电脑终端运行 btir-phone start，再重试上传。');
        }
        url = `http://10.0.2.2:18766${path}`;
        viaBridge = true;
      }

      httpRequest = http.createHttp();
      httpRequest.on('dataSendProgress', (progress: http.DataSendProgressInfo) => {
        uploadedBytes += progress.sendSize;
        uploadTotalBytes = progress.totalSize;
        if (uploadTotalBytes > 0) {
          const percent = Math.min(100, Math.floor(uploadedBytes * 100 / uploadTotalBytes));
          if (percent >= lastProgressPercent + 5 || percent === 100) {
            lastProgressPercent = percent;
            onStage?.(percent < 100 ? `正在上传 ${percent}%…` : '上传完成，等待服务器处理…');
          }
        }
      });
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        multiFormDataList: formData,
        connectTimeout: 30000,
        readTimeout: 600000,
      };
      preparingFiles = false;
      onStage?.(viaBridge ? '正在通过电脑转发上传…' : '正在上传并等待服务器处理…');
      const response = await httpRequest.request(url, options);

      const status = response.responseCode;
      const responseText = response.result as string;
      let responseData: Object | string = responseText;
      try {
        responseData = JSON.parse(responseText);
      } catch (e) {
        // 非 JSON
      }

      if (status >= 400) {
        throw new ApiError(status, responseData);
      }

      return responseData as T;
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      const prefix = preparingFiles ? '读取所选文件失败' : '网络上传失败';
      const detail = error as NativeErrorDetail;
      const code = detail && detail.code !== undefined ? `（错误码 ${detail.code}）` : '';
      const message = detail && detail.message ? detail.message : String(error);
      if (detail && Number(detail.code) === 23000056) {
        const progressText = uploadTotalBytes > 0
          ? `（已发送 ${Math.min(100, Math.floor(uploadedBytes * 100 / uploadTotalBytes))}%）` : '';
        throw new ApiError(0, message,
          `上传连接中断${progressText}。请确认 btir-phone start 已运行后重试。错误码 23000056`);
      }
      throw new ApiError(0, message, `${prefix}${code}：${message}`);
    } finally {
      if (httpRequest) {
        httpRequest.destroy();
      }
      for (const path of temporaryPaths) {
        try {
          await fs.unlink(path);
        } catch (error) {
          // 缓存文件可能尚未创建成功。
        }
      }
    }
  }

  async downloadFile(path: string): Promise<ArrayBuffer> {
    const baseUrl = ApiConfig.getInstance().baseUrl;
    const url = `${baseUrl}${path}`;
    const headers: Record<string, string> = {};
    const token = this.tokenManager.getToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    try {
      const httpRequest = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      };

      const response = await httpRequest.request(url, options);
      httpRequest.destroy();

      if (response.responseCode >= 400) {
        throw new ApiError(response.responseCode, String(response.result));
      }

      return response.result as ArrayBuffer;
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError(0, String(error), `文件下载失败: ${String(error)}`);
    }
  }

  arrayBufferToBase64(bufferData: ArrayBuffer): string {
    const buf = buffer.from(bufferData);
    return buf.toString('base64');
  }
}

export class TokenManager {
  private static instance: TokenManager | null = null;
  private _token: string = '';
  private _userId: string = '';
  private _username: string = '';
  private _role: string = '';
  private _mustChangePassword: boolean = false;

  private constructor() {
    this._token = AppStorage.get<string>('auth_token') ?? '';
    this._userId = AppStorage.get<string>('auth_user_id') ?? '';
    this._username = AppStorage.get<string>('auth_username') ?? '';
    this._role = AppStorage.get<string>('auth_role') ?? '';
    this._mustChangePassword = AppStorage.get<boolean>('auth_must_change_password') ?? false;
  }

  static getInstance(): TokenManager {
    if (!TokenManager.instance) {
      TokenManager.instance = new TokenManager();
    }
    return TokenManager.instance;
  }

  getToken(): string {
    return this._token;
  }

  setAuth(token: string, userId: string, username: string, role: string, mustChangePassword: boolean): void {
    this._token = token;
    this._userId = userId;
    this._username = username;
    this._role = role;
    this._mustChangePassword = mustChangePassword;
    AppStorage.setOrCreate<string>('auth_token', token);
    AppStorage.setOrCreate<string>('auth_user_id', userId);
    AppStorage.setOrCreate<string>('auth_username', username);
    AppStorage.setOrCreate<string>('auth_role', role);
    AppStorage.setOrCreate<boolean>('auth_must_change_password', mustChangePassword);
  }

  clearAuth(): void {
    this._token = '';
    this._userId = '';
    this._username = '';
    this._role = '';
    this._mustChangePassword = false;
    AppStorage.setOrCreate<string>('auth_token', '');
    AppStorage.setOrCreate<string>('auth_user_id', '');
    AppStorage.setOrCreate<string>('auth_username', '');
    AppStorage.setOrCreate<string>('auth_role', '');
    AppStorage.setOrCreate<boolean>('auth_must_change_password', false);
  }

  isLoggedIn(): boolean {
    return this._token.length > 0;
  }

  get mustChangePassword(): boolean {
    return this._mustChangePassword;
  }

  get username(): string {
    return this._username;
  }

  get role(): string {
    return this._role;
  }

  get userId(): string {
    return this._userId;
  }
}
