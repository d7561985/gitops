import { Provider } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { WAGER_SERVICE, IWagerService } from './wager.port';
import { WagerRestAdapter } from './wager-rest.adapter';
import { WagerConnectAdapter } from './wager-connect.adapter';

export * from './wager.port';
export { WagerRestAdapter } from './wager-rest.adapter';
export { WagerConnectAdapter } from './wager-connect.adapter';

/**
 * Factory function for creating wager service based on protocol config
 */
export function wagerServiceFactory(http: HttpClient): IWagerService {
  if (environment.useConnectProtocol) {
    return new WagerConnectAdapter();
  }
  return new WagerRestAdapter(http);
}

/**
 * Provider for IWagerService
 * Switches between REST and Connect based on environment.useConnectProtocol
 */
export const WAGER_SERVICE_PROVIDER: Provider = {
  provide: WAGER_SERVICE,
  useFactory: wagerServiceFactory,
  deps: [HttpClient],
};
