export interface AuthResponse {
  access_token: string;
  token_type: string;
  user_id: string;
  username: string;
  role: string;
  must_change_password: boolean;
}

export interface UserInfoResponse {
  user_id: string;
  username: string;
  role: string;
  is_active: boolean;
  must_change_password: boolean;
  created_at: string;
}

export interface ChangePasswordRequest {
  current_password: string;
  new_password: string;
}

export interface LoginRequest {
  username: string;
  password: string;
}

export interface RegisterRequest {
  username: string;
  password: string;
}
