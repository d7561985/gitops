import { Provider } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { GAME_ENGINE_SERVICE, IGameEngineService } from './game-engine.port';
import { GameEngineRestAdapter } from './game-engine-rest.adapter';
import { GameEngineConnectAdapter } from './game-engine-connect.adapter';

export * from './game-engine.port';
export { GameEngineRestAdapter } from './game-engine-rest.adapter';
export { GameEngineConnectAdapter } from './game-engine-connect.adapter';

/**
 * Factory function for creating game engine service based on protocol config
 */
export function gameEngineServiceFactory(http: HttpClient): IGameEngineService {
  if (environment.useConnectProtocol) {
    return new GameEngineConnectAdapter();
  }
  return new GameEngineRestAdapter(http);
}

/**
 * Provider for IGameEngineService
 * Switches between REST and Connect based on environment.useConnectProtocol
 */
export const GAME_ENGINE_SERVICE_PROVIDER: Provider = {
  provide: GAME_ENGINE_SERVICE,
  useFactory: gameEngineServiceFactory,
  deps: [HttpClient],
};
