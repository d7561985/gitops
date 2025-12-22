import { Provider } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { BONUS_SERVICE, IBonusService } from './bonus.port';
import { BonusRestAdapter } from './bonus-rest.adapter';
import { BonusConnectAdapter } from './bonus-connect.adapter';

export * from './bonus.port';
export { BonusRestAdapter } from './bonus-rest.adapter';
export { BonusConnectAdapter } from './bonus-connect.adapter';

/**
 * Factory function for creating bonus service based on protocol config
 */
export function bonusServiceFactory(http: HttpClient): IBonusService {
  if (environment.useConnectProtocol) {
    return new BonusConnectAdapter();
  }
  return new BonusRestAdapter(http);
}

/**
 * Provider for IBonusService
 * Switches between REST and Connect based on environment.useConnectProtocol
 */
export const BONUS_SERVICE_PROVIDER: Provider = {
  provide: BONUS_SERVICE,
  useFactory: bonusServiceFactory,
  deps: [HttpClient],
};
