import { Injectable } from '@angular/core';
import { createClient, type Client } from '@connectrpc/connect';
import { createConnectTransport } from '@connectrpc/connect-web';
import { BonusService } from '@gitops-poc-dzha/wager-service-web/wager/v1/bonus_pb';
import { environment } from '../../../environments/environment';
import { IBonusService, BonusProgress, ClaimResult, ConvertResult } from './bonus.port';

/**
 * Connect Protocol Adapter for Bonus Service
 * Uses Connect-ES client with auto-generated types from proto
 *
 * Benefits over plain HttpClient:
 * - Type-safe requests/responses
 * - Proto3 default values handled automatically (no more `?? 0`)
 * - Less boilerplate code
 */
@Injectable()
export class BonusConnectAdapter implements IBonusService {
  private readonly client: Client<typeof BonusService>;

  constructor() {
    const transport = createConnectTransport({
      baseUrl: (environment.apiUrl || '') + '/api/bonusconnect',
    });
    this.client = createClient(BonusService, transport);
  }

  async getProgress(userId: string): Promise<BonusProgress> {
    const response = await this.client.getProgress({ userId });

    return {
      hasActiveBonus: response.hasActiveBonus,
      bonus: response.hasActiveBonus ? {
        id: '',
        type: 'WELCOME',
        amount: response.bonusBalance,
        wageringRequired: response.wageringRequired,
        wageringCompleted: response.wageredAmount,
        progressPercent: response.progressPercent,
        status: response.canConvert ? 'completed' : 'active',
        expiresAt: response.expiresAt,
      } : undefined,
      balance: {
        real: response.realBalance,
        bonus: response.bonusBalance,
        total: response.realBalance + response.bonusBalance,
      },
    };
  }

  async claim(userId: string): Promise<ClaimResult> {
    const response = await this.client.claim({ userId });

    return {
      success: response.success,
      bonusId: response.bonusId,
      amount: response.amount,
      wageringRequired: response.wageringRequired,
      error: response.error || undefined,
    };
  }

  async convert(userId: string): Promise<ConvertResult> {
    const response = await this.client.convert({ userId });

    return {
      success: response.success,
      convertedAmount: response.convertedAmount,
      newBalance: response.newBalance,
      error: response.error || undefined,
    };
  }
}
