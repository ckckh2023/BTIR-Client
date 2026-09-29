export class ApiConfig {
  private static instance: ApiConfig | null = null;
  private _baseUrl: string = 'https://btir-online.ai-premol.cn';

  private constructor() {
    const stored = AppStorage.get<string>('api_base_url');
    if (stored) {
      this._baseUrl = stored;
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

  setBaseUrl(url: string): void {
    this._baseUrl = url.replace(/\/+$/, '');
    AppStorage.setOrCreate<string>('api_base_url', this._baseUrl);
  }
}
