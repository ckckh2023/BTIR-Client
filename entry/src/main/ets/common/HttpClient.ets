import { http } from '@kit.NetworkKit';
import { ApiConfig } from './ApiConfig';
import { ApiError } from './ApiError';
import { buffer } from '@kit.ArkTS';

interface FileUploadData {
  name: string;
  type: string;
  uri: string;
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

  async uploadFile<T>(path: string, fileUri: string, fileName: string, fileType: string,
    extraFields?: Record<string, string>): Promise<T> {
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
        method: http.RequestMethod.POST,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
      };

      const formData: Record<string, Object> = {};
      const archiveFile: FileUploadData = {
        name: fileName,
        type: fileType,
        uri: fileUri,
      };
      formData['archive'] = archiveFile;
      if (extraFields) {
        for (const key of Object.keys(extraFields)) {
          formData[key] = extraFields[key];
        }
      }
      options.extraData = formData;

      const response = await httpRequest.request(url, options);
      httpRequest.destroy();

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
      throw new ApiError(0, String(error), `文件上传失败: ${String(error)}`);
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
