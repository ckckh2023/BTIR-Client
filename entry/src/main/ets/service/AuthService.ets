import { HttpClient, TokenManager } from '../common/HttpClient';
import { ApiError } from '../common/ApiError';
import { AuthResponse, UserInfoResponse, ChangePasswordRequest, LoginRequest } from '../model/AuthModels';

export class AuthService {
  private httpClient: HttpClient = HttpClient.getInstance();

  async login(username: string, password: string): Promise<AuthResponse> {
    const request: LoginRequest = { username, password };
    const response = await this.httpClient.post<AuthResponse>('/auth/login', request);
    TokenManager.getInstance().setAuth(
      response.access_token,
      response.user_id,
      response.username,
      response.role,
      response.must_change_password
    );
    return response;
  }

  async getCurrentUser(): Promise<UserInfoResponse> {
    return this.httpClient.get<UserInfoResponse>('/auth/me');
  }

  async changePassword(currentPassword: string, newPassword: string): Promise<AuthResponse> {
    const request: ChangePasswordRequest = {
      current_password: currentPassword,
      new_password: newPassword,
    };
    const response = await this.httpClient.post<AuthResponse>('/auth/change-password', request);
    TokenManager.getInstance().setAuth(
      response.access_token,
      response.user_id,
      response.username,
      response.role,
      response.must_change_password
    );
    return response;
  }

  logout(): void {
    TokenManager.getInstance().clearAuth();
  }
}
