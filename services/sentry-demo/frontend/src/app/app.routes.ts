import { Routes } from '@angular/router';
import { SlotMachineComponent } from './slot-machine/slot-machine.component';

export const routes: Routes = [
  { path: '', component: SlotMachineComponent },
  {
    path: 'metrics',
    loadComponent: () => import('./business-metrics/business-metrics.component')
      .then(m => m.BusinessMetricsComponent)
  },
  {
    path: 'auth',
    loadComponent: () => import('./auth/auth.component')
      .then(m => m.AuthComponent)
  }
];