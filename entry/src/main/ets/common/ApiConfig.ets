import { preferences } from '@kit.ArkData';
import { normalizeServerUrl } from './ServerUrl';

export class ApiConfig {
  static readonly DEFAULT_BASE_URL: string = 'https://btir-online.ai-premol.cn';
  private static instance: ApiConfig | null = null;
  private _baseUrl: string = ApiConfig.DEFAULT_BASE_URL;

  private storage: preferences.Preferences | null = null;

  private constructor() {}

  initialize(storage: preferences.Preferences): void {
    this.storage = storage;
    const saved = storage.getSync('api_base_url', ApiConfig.DEFAULT_BASE_URL);
    if (typeof saved === 'string') {
      try { this._baseUrl = normalizeServerUrl(saved); } catch (error) { /* 保留可用的默认地址。 */ }
    }
  }

  static getInstance(): ApiConfig {
    if (!ApiConfig.instance) {
      ApiConfig.instance = new ApiConfig();
    }
    return ApiConfig.instance;
  }

  get baseUrl(): string {
    return this._baseUrl;
  }

  setBaseUrl(url: string): boolean {
    const next = normalizeServerUrl(url);
    const changed = next !== this._baseUrl;
    if (this.storage) {
      this.storage.putSync('api_base_url', next);
      this.storage.flushSync();
    }
    this._baseUrl = next;
    return changed;
  }
}
