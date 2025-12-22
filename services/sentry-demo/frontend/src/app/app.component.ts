import { Component, inject } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from './services/auth.service';

@Component({
    selector: 'app-root',
    standalone: true,
    imports: [RouterOutlet, RouterLink, RouterLinkActive],
    template: `
    <div class="container">
      <nav class="main-nav">
        <a routerLink="/" routerLinkActive="active" [routerLinkActiveOptions]="{exact: true}">Game</a>
        <a routerLink="/metrics" routerLinkActive="active">Metrics</a>
        <a routerLink="/auth" routerLinkActive="active">
          @if (authService.isAuthenticated()) {
            {{ authService.currentUser()?.username }}
          } @else {
            Login
          }
        </a>
      </nav>

      <h1 style="text-align: center; margin: 20px 0;">Sentry POC - iGaming Demo</h1>

      @defer (on viewport) {
        <router-outlet></router-outlet>
      } @placeholder {
        <div style="text-align: center; padding: 40px;">
          <p>Loading...</p>
        </div>
      }
    </div>
  `,
    styles: [`
      .main-nav {
        display: flex;
        justify-content: center;
        gap: 20px;
        padding: 15px;
        background: #1a1a2e;
        border-radius: 8px;
        margin-bottom: 10px;
      }

      .main-nav a {
        color: #888;
        text-decoration: none;
        padding: 8px 16px;
        border-radius: 6px;
        transition: all 0.3s;
      }

      .main-nav a:hover {
        color: #fff;
        background: #2a2a4a;
      }

      .main-nav a.active {
        color: #4CAF50;
        background: rgba(76, 175, 80, 0.2);
      }
    `]
})
export class AppComponent {
  title = 'sentry-poc-frontend';
  authService = inject(AuthService);
}