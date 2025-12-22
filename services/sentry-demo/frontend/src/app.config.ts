import { ApplicationConfig, ErrorHandler } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptorsFromDi } from '@angular/common/http';

import { routes } from './app/app.routes';
import { SentryErrorHandler } from './app/services/sentry-error.handler';

// Clean Architecture: Protocol-agnostic service providers
import { GAME_ENGINE_SERVICE_PROVIDER } from './app/services/game-engine';
import { BONUS_SERVICE_PROVIDER } from './app/services/bonus';
import { WAGER_SERVICE_PROVIDER } from './app/services/wager';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient(withInterceptorsFromDi()),
    { provide: ErrorHandler, useClass: SentryErrorHandler },
    // Clean Architecture: Protocol-agnostic service providers
    GAME_ENGINE_SERVICE_PROVIDER,
    BONUS_SERVICE_PROVIDER,
    WAGER_SERVICE_PROVIDER,
  ]
};