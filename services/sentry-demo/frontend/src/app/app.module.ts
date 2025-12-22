import { NgModule, ErrorHandler } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { provideHttpClient, withInterceptorsFromDi } from '@angular/common/http';
import { RouterModule } from '@angular/router';

import { AppComponent } from './app.component';
import { SlotMachineComponent } from './slot-machine/slot-machine.component';
import { BusinessMetricsComponent } from './business-metrics/business-metrics.component';
import { AuthService } from './services/auth.service';
import { SentryErrorHandler } from './services/sentry-error.handler';

// Clean Architecture: Service providers with protocol switching
import { GAME_ENGINE_SERVICE_PROVIDER } from './services/game-engine';
import { BONUS_SERVICE_PROVIDER } from './services/bonus';
import { WAGER_SERVICE_PROVIDER } from './services/wager';

@NgModule({
    imports: [
        BrowserModule,
        AppComponent,
        SlotMachineComponent,
        BusinessMetricsComponent,
        RouterModule.forRoot([
            { path: '', component: SlotMachineComponent },
            { path: 'metrics', component: BusinessMetricsComponent }
        ])
    ],
    providers: [
        AuthService,
        // Clean Architecture: Protocol-agnostic service providers
        GAME_ENGINE_SERVICE_PROVIDER,
        BONUS_SERVICE_PROVIDER,
        WAGER_SERVICE_PROVIDER,
        {
            provide: ErrorHandler,
            useClass: SentryErrorHandler
        },
        provideHttpClient(withInterceptorsFromDi()),
    ],
    bootstrap: [AppComponent]
})
export class AppModule { }