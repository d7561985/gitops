import { Injectable, signal, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../environments/environment';

/**
 * User data interface
 */
export interface User {
  userId: string;
  email: string;
  username: string;
  roles: string[];
}

/**
 * Token storage interface
 */
interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

/**
 * Authentication Service for user-service integration
 *
 * Uses Connect protocol (HTTP POST + JSON) for user-service API.
 * Connect protocol advantages:
 * - Works through any HTTP proxy (Cloudflare, nginx, etc.)
 * - No trailer issues - uses standard HTTP POST with JSON
 * - Human-readable in DevTools (Content-Type: application/json)
 *
 * API Gateway routes: /api/user/* -> user-service (Connect protocol)
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private readonly baseUrl = (environment.apiUrl || '') + '/api/user';

  // Reactive state using Angular signals
  private _currentUser = signal<User | null>(null);
  private _isAuthenticated = signal<boolean>(false);
  private _isLoading = signal<boolean>(false);
  private _error = signal<string | null>(null);

  // Public readonly signals
  currentUser = this._currentUser.asReadonly();
  isAuthenticated = this._isAuthenticated.asReadonly();
  isLoading = this._isLoading.asReadonly();
  error = this._error.asReadonly();

  constructor() {
    // Check for existing tokens on init
    this.checkExistingAuth();
  }

  /**
   * Register a new user account
   */
  async register(email: string, password: string, username: string): Promise<boolean> {
    this._isLoading.set(true);
    this._error.set(null);

    try {
      const response = await firstValueFrom(
        this.http.post<any>(`${this.baseUrl}/user.v1.UserService/Register`, {
          email,
          password,
          username
        }, { headers: this.getHttpHeaders() })
      );

      this.storeTokens({
        accessToken: response.accessToken,
        refreshToken: response.refreshToken
      });

      this._currentUser.set({
        userId: response.userId,
        email,
        username,
        roles: ['CLIENT']
      });
      this._isAuthenticated.set(true);

      return true;
    } catch (err) {
      this._error.set(this.extractErrorMessage(err));
      return false;
    } finally {
      this._isLoading.set(false);
    }
  }

  /**
   * Login with email and password
   */
  async login(email: string, password: string): Promise<boolean> {
    this._isLoading.set(true);
    this._error.set(null);

    try {
      const response = await firstValueFrom(
        this.http.post<any>(`${this.baseUrl}/user.v1.UserService/Login`, {
          email,
          password
        }, { headers: this.getHttpHeaders() })
      );

      this.storeTokens({
        accessToken: response.accessToken,
        refreshToken: response.refreshToken
      });

      // Fetch user profile after login
      await this.fetchProfile();

      return true;
    } catch (err) {
      this._error.set(this.extractErrorMessage(err));
      return false;
    } finally {
      this._isLoading.set(false);
    }
  }

  /**
   * Logout current user
   */
  async logout(): Promise<void> {
    this._isLoading.set(true);

    try {
      await firstValueFrom(
        this.http.post<any>(`${this.baseUrl}/user.v1.UserService/Logout`, {}, {
          headers: this.getHttpHeaders()
        })
      );
    } catch (err) {
      // Ignore logout errors - clear local state anyway
      console.warn('Logout request failed:', err);
    } finally {
      this.clearAuth();
      this._isLoading.set(false);
    }
  }

  /**
   * Refresh access token using refresh token
   */
  async refreshToken(): Promise<boolean> {
    const tokens = this.getStoredTokens();
    if (!tokens?.refreshToken) {
      return false;
    }

    try {
      const response = await firstValueFrom(
        this.http.post<any>(`${this.baseUrl}/user.v1.UserService/RefreshToken`, {
          refreshToken: tokens.refreshToken
        })
      );

      this.storeTokens({
        accessToken: response.accessToken,
        refreshToken: response.refreshToken
      });

      return true;
    } catch (err) {
      this.clearAuth();
      return false;
    }
  }

  /**
   * Get current user profile from server
   */
  async fetchProfile(): Promise<User | null> {
    try {
      const response = await firstValueFrom(
        this.http.post<any>(`${this.baseUrl}/user.v1.UserService/GetProfile`, {}, {
          headers: this.getHttpHeaders()
        })
      );

      const user: User = {
        userId: response.userId,
        email: response.email,
        username: response.username,
        roles: response.roles?.length > 0 ? response.roles : ['CLIENT']
      };

      this._currentUser.set(user);
      this._isAuthenticated.set(true);

      return user;
    } catch (err) {
      this._error.set(this.extractErrorMessage(err));
      return null;
    }
  }

  /**
   * Get current access token for other services
   */
  getAccessToken(): string | null {
    return this.getStoredTokens()?.accessToken || null;
  }

  /**
   * Clear current error
   */
  clearError(): void {
    this._error.set(null);
  }

  // ==================== Private Methods ====================

  /**
   * Get HTTP headers with authorization token
   */
  private getHttpHeaders(): HttpHeaders {
    const token = this.getAccessToken();
    let headers = new HttpHeaders({ 'Content-Type': 'application/json' });
    if (token) {
      headers = headers.set('Authorization', `Bearer ${token}`);
    }
    return headers;
  }

  /**
   * Extract error message from HTTP error
   */
  private extractErrorMessage(err: unknown): string {
    if (err && typeof err === 'object') {
      const httpError = err as { error?: { message?: string; code?: string }; message?: string };
      if (httpError.error?.message) {
        return httpError.error.message;
      }
      if (httpError.message) {
        return httpError.message;
      }
    }
    return 'Unknown error occurred';
  }

  /**
   * Check for existing authentication on service init
   */
  private checkExistingAuth(): void {
    const tokens = this.getStoredTokens();
    if (tokens?.accessToken) {
      // Verify token by fetching profile
      this.fetchProfile().catch(() => this.clearAuth());
    }
  }

  /**
   * Store tokens in localStorage
   */
  private storeTokens(tokens: AuthTokens): void {
    localStorage.setItem('auth_tokens', JSON.stringify(tokens));
  }

  /**
   * Get stored tokens from localStorage
   */
  private getStoredTokens(): AuthTokens | null {
    const stored = localStorage.getItem('auth_tokens');
    if (!stored) return null;

    try {
      return JSON.parse(stored) as AuthTokens;
    } catch {
      return null;
    }
  }

  /**
   * Clear all authentication state
   */
  private clearAuth(): void {
    localStorage.removeItem('auth_tokens');
    this._currentUser.set(null);
    this._isAuthenticated.set(false);
    this._error.set(null);
  }
}
