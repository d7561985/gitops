import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

@Component({
  selector: 'app-auth',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  template: `
    <div class="auth-container">
      <div class="auth-card">
        <div class="auth-tabs">
          <button
            [class.active]="mode === 'login'"
            (click)="mode = 'login'; clearError()">
            Login
          </button>
          <button
            [class.active]="mode === 'register'"
            (click)="mode = 'register'; clearError()">
            Register
          </button>
        </div>

        @if (mode === 'login') {
          <form [formGroup]="loginForm" (ngSubmit)="onLogin()">
            <div class="form-group">
              <label for="login-email">Email</label>
              <input
                id="login-email"
                type="email"
                formControlName="email"
                placeholder="Enter your email">
              @if (loginForm.get('email')?.invalid && loginForm.get('email')?.touched) {
                <span class="error-hint">Valid email required</span>
              }
            </div>

            <div class="form-group">
              <label for="login-password">Password</label>
              <input
                id="login-password"
                type="password"
                formControlName="password"
                placeholder="Enter your password">
              @if (loginForm.get('password')?.invalid && loginForm.get('password')?.touched) {
                <span class="error-hint">Password required</span>
              }
            </div>

            <button
              type="submit"
              class="submit-btn"
              [disabled]="loginForm.invalid || authService.isLoading()">
              {{ authService.isLoading() ? 'Logging in...' : 'Login' }}
            </button>
          </form>
        }

        @if (mode === 'register') {
          <form [formGroup]="registerForm" (ngSubmit)="onRegister()">
            <div class="form-group">
              <label for="reg-username">Username</label>
              <input
                id="reg-username"
                type="text"
                formControlName="username"
                placeholder="Choose a username">
              @if (registerForm.get('username')?.invalid && registerForm.get('username')?.touched) {
                <span class="error-hint">Username required (3+ characters)</span>
              }
            </div>

            <div class="form-group">
              <label for="reg-email">Email</label>
              <input
                id="reg-email"
                type="email"
                formControlName="email"
                placeholder="Enter your email">
              @if (registerForm.get('email')?.invalid && registerForm.get('email')?.touched) {
                <span class="error-hint">Valid email required</span>
              }
            </div>

            <div class="form-group">
              <label for="reg-password">Password</label>
              <input
                id="reg-password"
                type="password"
                formControlName="password"
                placeholder="Create a password">
              @if (registerForm.get('password')?.invalid && registerForm.get('password')?.touched) {
                <span class="error-hint">Password required (6+ characters)</span>
              }
            </div>

            <button
              type="submit"
              class="submit-btn"
              [disabled]="registerForm.invalid || authService.isLoading()">
              {{ authService.isLoading() ? 'Creating account...' : 'Register' }}
            </button>
          </form>
        }

        @if (authService.error()) {
          <div class="error-message">
            {{ authService.error() }}
          </div>
        }

        @if (authService.isAuthenticated()) {
          <div class="success-message">
            Authenticated as {{ authService.currentUser()?.username }}
            <button class="logout-btn" (click)="onLogout()">Logout</button>
          </div>
        }
      </div>
    </div>
  `,
  styles: [`
    .auth-container {
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 60vh;
      padding: 20px;
    }

    .auth-card {
      background: #1a1a2e;
      border-radius: 12px;
      padding: 30px;
      width: 100%;
      max-width: 400px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
    }

    .auth-tabs {
      display: flex;
      gap: 10px;
      margin-bottom: 25px;
    }

    .auth-tabs button {
      flex: 1;
      padding: 12px;
      border: none;
      background: #2a2a4a;
      color: #888;
      border-radius: 8px;
      cursor: pointer;
      font-size: 16px;
      transition: all 0.3s;
    }

    .auth-tabs button.active {
      background: #4CAF50;
      color: white;
    }

    .auth-tabs button:hover:not(.active) {
      background: #3a3a5a;
    }

    .form-group {
      margin-bottom: 20px;
    }

    .form-group label {
      display: block;
      margin-bottom: 8px;
      color: #ccc;
      font-size: 14px;
    }

    .form-group input {
      width: 100%;
      padding: 12px;
      border: 2px solid #3a3a5a;
      border-radius: 8px;
      background: #2a2a4a;
      color: white;
      font-size: 16px;
      box-sizing: border-box;
      transition: border-color 0.3s;
    }

    .form-group input:focus {
      outline: none;
      border-color: #4CAF50;
    }

    .form-group input::placeholder {
      color: #666;
    }

    .error-hint {
      color: #FF6B6B;
      font-size: 12px;
      margin-top: 5px;
      display: block;
    }

    .submit-btn {
      width: 100%;
      padding: 14px;
      border: none;
      border-radius: 8px;
      background: #4CAF50;
      color: white;
      font-size: 16px;
      font-weight: bold;
      cursor: pointer;
      transition: all 0.3s;
    }

    .submit-btn:hover:not(:disabled) {
      background: #45a049;
      transform: translateY(-2px);
    }

    .submit-btn:disabled {
      background: #666;
      cursor: not-allowed;
    }

    .error-message {
      margin-top: 20px;
      padding: 12px;
      background: rgba(255, 107, 107, 0.2);
      border: 1px solid #FF6B6B;
      border-radius: 8px;
      color: #FF6B6B;
      text-align: center;
    }

    .success-message {
      margin-top: 20px;
      padding: 12px;
      background: rgba(76, 175, 80, 0.2);
      border: 1px solid #4CAF50;
      border-radius: 8px;
      color: #4CAF50;
      text-align: center;
    }

    .logout-btn {
      margin-left: 10px;
      padding: 6px 12px;
      border: 1px solid #4CAF50;
      background: transparent;
      color: #4CAF50;
      border-radius: 4px;
      cursor: pointer;
      font-size: 12px;
    }

    .logout-btn:hover {
      background: rgba(76, 175, 80, 0.2);
    }
  `]
})
export class AuthComponent {
  mode: 'login' | 'register' = 'login';

  loginForm: FormGroup;
  registerForm: FormGroup;

  constructor(
    private fb: FormBuilder,
    public authService: AuthService,
    private router: Router
  ) {
    this.loginForm = this.fb.group({
      email: ['', [Validators.required, Validators.email]],
      password: ['', Validators.required]
    });

    this.registerForm = this.fb.group({
      username: ['', [Validators.required, Validators.minLength(3)]],
      email: ['', [Validators.required, Validators.email]],
      password: ['', [Validators.required, Validators.minLength(6)]]
    });
  }

  async onLogin(): Promise<void> {
    if (this.loginForm.invalid) return;

    const { email, password } = this.loginForm.value;
    const success = await this.authService.login(email, password);

    if (success) {
      this.router.navigate(['/']);
    }
  }

  async onRegister(): Promise<void> {
    if (this.registerForm.invalid) return;

    const { email, password, username } = this.registerForm.value;
    const success = await this.authService.register(email, password, username);

    if (success) {
      this.router.navigate(['/']);
    }
  }

  async onLogout(): Promise<void> {
    await this.authService.logout();
  }

  clearError(): void {
    this.authService.clearError();
  }
}
