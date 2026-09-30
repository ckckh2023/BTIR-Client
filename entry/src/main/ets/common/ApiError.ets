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

  private static payload(detail: Object | string): Record<string, Object> | null {
    if (typeof detail !== 'object' || detail === null) {
      return null;
    }
    const response = detail as Record<string, Object>;
    const nested = response['detail'];
    if (typeof nested === 'object' && nested !== null) {
      return nested as Record<string, Object>;
    }
    return response;
  }

  private static extractMessage(detail: Object | string): string {
    if (typeof detail === 'string') {
      return detail;
    }
    const response = detail as Record<string, Object>;
    const validationErrors = response['detail'];
    if (Array.isArray(validationErrors) && validationErrors.length > 0) {
      const firstError = validationErrors[0] as Record<string, Object>;
      if (typeof firstError['msg'] === 'string') {
        return (firstError['msg'] as string).replace(/^Value error,\s*/, '');
      }
    }
    const obj = ApiError.payload(detail);
    if (obj && typeof obj['message'] === 'string') {
      return obj['message'] as string;
    }
    if (obj && typeof obj['detail'] === 'string') {
      return obj['detail'] as string;
    }
    return JSON.stringify(detail);
  }

  private static extractCode(detail: Object | string): string {
    const obj = ApiError.payload(detail);
    if (obj && typeof obj['code'] === 'string') {
      return obj['code'] as string;
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
    if (this.isModalitySelection()) {
      const obj = ApiError.payload(this.detail);
      if (!obj) {
        return null;
      }
      if (obj['modalities']) {
        return obj['modalities'] as Record<string, Object>;
      }
    }
    return null;
  }
}
