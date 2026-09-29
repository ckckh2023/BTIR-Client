import { TokenManager } from '../common/HttpClient';

@ObservedV2
export class AppState {
  @Trace
  isLoggedIn: boolean = false;

  @Trace
  username: string = '';

  @Trace
  mustChangePassword: boolean = false;

  @Trace
  currentTaskId: string = '';

  @Trace
  isLoading: boolean = false;

  @Trace
  errorMessage: string = '';

  private tokenManager: TokenManager = TokenManager.getInstance();

  constructor() {
    this.refreshAuthState();
  }

  refreshAuthState(): void {
    this.isLoggedIn = this.tokenManager.isLoggedIn();
    this.username = this.tokenManager.username;
    this.mustChangePassword = this.tokenManager.mustChangePassword;
  }

  setLoggedIn(token: string, userId: string, username: string, role: string, mustChangePassword: boolean): void {
    this.tokenManager.setAuth(token, userId, username, role, mustChangePassword);
    this.refreshAuthState();
  }

  logout(): void {
    this.tokenManager.clearAuth();
    this.refreshAuthState();
    this.currentTaskId = '';
  }

  setLoading(loading: boolean): void {
    this.isLoading = loading;
  }

  setError(message: string): void {
    this.errorMessage = message;
  }

  clearError(): void {
    this.errorMessage = '';
  }
}
