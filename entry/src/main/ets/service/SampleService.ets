import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ApiConfig } from '../common/ApiConfig';
import { ApiError } from '../common/ApiError';

export interface SampleCase {
  title: string;
  fileName: string;
}

// 与网页端 guide.html 的公开样例保持一致。
export const SAMPLE_CASES: SampleCase[] = [
  { title: '病例 1', fileName: 'BraTS19_2013_2_1.zip' },
  { title: '病例 2', fileName: 'BraTS19_2013_4_1.zip' },
  { title: '病例 3', fileName: 'BraTS19_2013_7_1.zip' }
];

export class SampleDownloadCancelled extends Error {
  constructor() { super('已取消下载'); }
}

interface DownloadError {
  code?: number;
  message?: string;
}

export class SampleService {
  private cancelActive: (() => void) | null = null;

  cancel(): void {
    this.cancelActive?.();
  }

  async download(sample: SampleCase, cacheDir: string,
    onProgress: (received: number, total: number) => void): Promise<string> {
    if (this.cancelActive) throw new Error('已有样例正在下载');
    if (!SAMPLE_CASES.some((item: SampleCase) => item.fileName === sample.fileName)) {
      throw new Error('未知的测试样例');
    }
    const path = `${cacheDir}/btir-sample-${Date.now()}.zip`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const request = http.createHttp();
    let received = 0;
    let total = 0;
    let timer = -1;
    let fileClosed = false;
    try {
      const status = await new Promise<number>((resolve, reject) => {
        let settled = false;
        let ended = false;
        let responseCode = 0;
        const fail = (error: Error | ApiError | SampleDownloadCancelled): void => {
          if (settled) return;
          settled = true;
          reject(error);
        };
        const complete = (): void => {
          if (settled || !ended || !responseCode) return;
          settled = true;
          resolve(responseCode);
        };
        this.cancelActive = (): void => { fail(new SampleDownloadCancelled()); };
        timer = setTimeout(() => {
          fail(new Error('样例下载超时，请检查网络后重试'));
        }, 180000);
        request.on('headersReceive', (headers: Object) => {
          const values = headers as Record<string, Object>;
          for (const key of Object.keys(values)) {
            if (key.toLowerCase() === 'content-length') {
              const length = Number(values[key]);
              if (Number.isFinite(length) && length > 0) total = length;
            }
          }
        });
        request.on('dataReceive', (data: ArrayBuffer) => {
          if (settled) return;
          try {
            if (received + data.byteLength > 64 * 1024 * 1024) {
              throw new Error('样例文件超过下载大小限制');
            }
            let offset = 0;
            while (offset < data.byteLength) {
              const written = fs.writeSync(file.fd, data.slice(offset));
              if (written <= 0) throw new Error('无法写入样例文件，请检查设备剩余空间');
              offset += written;
            }
            received += data.byteLength;
            onProgress(received, total);
          } catch (error) {
            fail(new Error((error as DownloadError).message || '写入样例失败'));
          }
        });
        request.on('dataEnd', () => {
          ended = true;
          complete();
        });
        // 样例为公开静态资源，不附带登录令牌。
        request.requestInStream(`${ApiConfig.getInstance().baseUrl}/assets/samples/${sample.fileName}`, {
          method: http.RequestMethod.GET,
          header: { 'Accept-Encoding': 'identity' },
          connectTimeout: 10000,
          readTimeout: 120000,
          usingCache: false
        }).then((code: number) => {
          responseCode = code;
          if (code !== 200) {
            fail(new ApiError(code, code === 404 ? '该样例暂不可用，请稍后重试' : `样例下载失败（HTTP ${code}）`));
          } else {
            complete();
          }
        }).catch((error: DownloadError) => {
          fail(new Error(`无法下载样例，请检查网络后重试${error.message ? `：${error.message}` : ''}`));
        });
      });
      if (status !== 200 || (total > 0 && received !== total)) {
        throw new Error('样例下载不完整，请重新下载');
      }
      fs.closeSync(file);
      fileClosed = true;
      this.verifyZip(path, received);
      return path;
    } catch (error) {
      try { fs.unlinkSync(path); } catch (cleanupError) { /* 文件可能已清理。 */ }
      if (error instanceof SampleDownloadCancelled || error instanceof ApiError || error instanceof Error) {
        throw error;
      }
      throw new Error((error as DownloadError).message || '样例下载失败');
    } finally {
      if (timer !== -1) clearTimeout(timer);
      this.cancelActive = null;
      request.destroy();
      if (!fileClosed) fs.closeSync(file);
    }
  }

  private verifyZip(path: string, size: number): void {
    if (size < 22) throw new Error('下载的样例不是完整 ZIP，请重试');
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const header = new ArrayBuffer(4);
      fs.readSync(file.fd, header);
      const magic = new Uint8Array(header);
      if (magic[0] !== 0x50 || magic[1] !== 0x4b || magic[2] !== 0x03 || magic[3] !== 0x04) {
        throw new Error('服务器未返回病例 ZIP，请稍后重试');
      }
      const length = Math.min(size, 65557);
      const tail = new ArrayBuffer(length);
      const count = fs.readSync(file.fd, tail, { offset: size - length, length: length });
      const bytes = new Uint8Array(tail);
      for (let index = count - 22; index >= 0; index--) {
        if (bytes[index] === 0x50 && bytes[index + 1] === 0x4b &&
          bytes[index + 2] === 0x05 && bytes[index + 3] === 0x06 &&
          index + 22 + (bytes[index + 20] | (bytes[index + 21] << 8)) === count) return;
      }
      throw new Error('样例 ZIP 下载不完整，请重试');
    } finally {
      fs.closeSync(file);
    }
  }
}
