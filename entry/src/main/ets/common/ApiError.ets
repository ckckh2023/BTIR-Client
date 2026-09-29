export class ApiError extends Error {
  statusCode: number = 0;
  detail: Object | string = '';
  code: string = '';
  retryAfter: number = 0;

  constructor(statusCode: number, detail: Object | string, message?: string) {
    super(message ?? ApiError.extractMessage(detail));
    this.statusCode = statusCode;
    this.detail = detail;
    this.code = ApiError.extractCode(detail);
    this.retryAfter = 0;
  }

  private static extractMessage(detail: Object | string): string {
    if (typeof detail === 'string') {
      return detail;
    }
    const obj = detail as Record<string, Object>;
    if (obj['message'] && typeof obj['message'] === 'string') {
      return obj['message'] as string;
    }
    if (obj['detail'] && typeof obj['detail'] === 'string') {
      return obj['detail'] as string;
    }
    return JSON.stringify(detail);
  }

  private static extractCode(detail: Object | string): string {
    if (typeof detail === 'object' && detail !== null) {
      const obj = detail as Record<string, Object>;
      if (obj['code'] && typeof obj['code'] === 'string') {
        return obj['code'] as string;
      }
    }
    return '';
  }

  isModalitySelection(): boolean {
    return this.code === 'archive_modality_selection_required' ||
      this.code === 'dicom_series_selection_required';
  }

  isTokenExpired(): boolean {
    return this.statusCode === 401;
  }

  isForbidden(): boolean {
    return this.statusCode === 403;
  }

  isRateLimited(): boolean {
    return this.statusCode === 429;
  }

  isServiceUnavailable(): boolean {
    return this.statusCode === 503;
  }

  getModalitySelectionData(): Record<string, Object> | null {
    if (this.isModalitySelection() && typeof this.detail === 'object') {
      const obj = this.detail as Record<string, Object>;
      if (obj['modalities']) {
        return obj['modalities'] as Record<string, Object>;
      }
    }
    return null;
  }
}
