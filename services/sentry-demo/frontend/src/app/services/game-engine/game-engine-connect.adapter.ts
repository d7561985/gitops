import { Injectable } from '@angular/core';
import { createClient, type Client } from '@connectrpc/connect';
import { createConnectTransport } from '@connectrpc/connect-web';
import { GameEngineService } from '@gitops-poc-dzha/game-engine-web/game/v1/game_pb';
import { environment } from '../../../environments/environment';
import { IGameEngineService, SpinResult, BusinessMetricsResult } from './game-engine.port';

/**
 * Connect Protocol Adapter for Game Engine Service
 * Uses Connect-ES client with auto-generated types from proto
 */
@Injectable()
export class GameEngineConnectAdapter implements IGameEngineService {
  private readonly client: Client<typeof GameEngineService>;

  constructor() {
    const transport = createConnectTransport({
      baseUrl: (environment.apiUrl || '') + '/api/gameconnect',
    });
    this.client = createClient(GameEngineService, transport);
  }

  async calculate(userId: string, bet: number, cpuIntensive = false): Promise<SpinResult> {
    const response = await this.client.calculate({ userId, bet, cpuIntensive });

    return {
      win: response.win,
      payout: response.payout,
      newBalance: response.newBalance,
      symbols: [...response.symbols],
      wageringProgress: response.wageringProgress ? {
        progressPercent: response.wageringProgress.progressPercent,
        remaining: response.wageringProgress.remaining,
        canConvert: response.wageringProgress.canConvert,
      } : undefined,
    };
  }

  async trackBusinessMetrics(scenario: string): Promise<BusinessMetricsResult> {
    const response = await this.client.trackBusinessMetrics({ scenario });

    return {
      status: response.status,
    };
  }
}
