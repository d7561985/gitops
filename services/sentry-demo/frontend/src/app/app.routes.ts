import { Routes } from '@angular/router';
import { SlotMachineComponent } from './slot-machine/slot-machine.component';
import { ANALYTICS_SERVICE_PROVIDER } from './services/analytics';

export const routes: Routes = [
  { path: '', component: SlotMachineComponent },
  {
    path: 'metrics',
    loadComponent: () => import('./business-metrics/business-metrics.component')
      .then(m => m.BusinessMetricsComponent),
    providers: [ANALYTICS_SERVICE_PROVIDER]
  },
  {
    path: 'auth',
    loadComponent: () => import('./auth/auth.component')
      .then(m => m.AuthComponent)
  }
];