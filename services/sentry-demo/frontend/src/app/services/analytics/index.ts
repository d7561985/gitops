import { Provider } from '@angular/core';
import { ANALYTICS_SERVICE, IAnalyticsService } from './analytics.port';
import { AnalyticsConnectAdapter } from './analytics-connect.adapter';

export * from './analytics.port';
export { AnalyticsConnectAdapter } from './analytics-connect.adapter';

/**
 * Factory function for creating analytics service
 * Uses Connect protocol only (no REST fallback needed for new service)
 */
export function analyticsServiceFactory(): IAnalyticsService {
  return new AnalyticsConnectAdapter();
}

/**
 * Provider for IAnalyticsService
 */
export const ANALYTICS_SERVICE_PROVIDER: Provider = {
  provide: ANALYTICS_SERVICE,
  useFactory: analyticsServiceFactory,
  deps: [],
};
