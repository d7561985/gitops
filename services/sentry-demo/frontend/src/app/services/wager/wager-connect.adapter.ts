import { Injectable } from '@angular/core';
import { createClient, type Client } from '@connectrpc/connect';
import { createConnectTransport } from '@connectrpc/connect-web';
import { WagerService } from '@gitops-poc-dzha/wager-service-web/wager/v1/wager_pb';
import { environment } from '../../../environments/environment';
import { IWagerService, ValidationResult, ValidationData, PlaceResult, WagerHistoryResult } from './wager.port';

/**
 * Connect Protocol Adapter for Wager Service
 * Uses Connect-ES client with auto-generated types from proto
 */
@Injectable()
export class WagerConnectAdapter implements IWagerService {
  private readonly client: Client<typeof WagerService>;

  constructor() {
    const transport = createConnectTransport({
      baseUrl: (environment.apiUrl || '') + '/api/wagerconnect',
    });
    this.client = createClient(WagerService, transport);
  }

  async validate(userId: string, amount: number, gameId: string): Promise<ValidationResult> {
    const response = await this.client.validate({ userId, amount, gameId });

    return {
      valid: response.valid,
      validationToken: response.validationToken,
      bonusUsed: response.bonusUsed,
      realUsed: response.realUsed,
      userId: response.userId,
      amount: response.amount,
      gameId: response.gameId,
    };
  }

  async place(validationData: ValidationData, gameResult: 'win' | 'lose', payout: number): Promise<PlaceResult> {
    const response = await this.client.place({
      validationData: {
        userId: validationData.userId,
        amount: validationData.amount,
        gameId: validationData.gameId,
        bonusUsed: validationData.bonusUsed,
        realUsed: validationData.realUsed,
        validationToken: validationData.validationToken,
      },
      gameResult,
      payout,
    });

    return {
      wagerId: response.wagerId,
      success: response.success,
      wageringProgress: response.wageringProgress ? {
        progressPercent: response.wageringProgress.progressPercent,
        remaining: response.wageringProgress.remaining,
        canConvert: response.wageringProgress.canConvert,
        totalRequired: response.wageringProgress.totalRequired,
        totalWagered: response.wageringProgress.totalWagered,
      } : undefined,
    };
  }

  async getHistory(userId: string, limit = 20): Promise<WagerHistoryResult> {
    const response = await this.client.getHistory({ userId, limit });

    return {
      wagers: response.wagers.map(w => ({
        wagerId: w.wagerId,
        userId: w.userId,
        gameId: w.gameId,
        amount: w.amount,
        gameResult: w.gameResult,
        payout: w.payout,
        bonusUsed: w.bonusUsed,
        realUsed: w.realUsed,
        createdAt: w.createdAt,
      })),
      totalCount: response.totalCount,
    };
  }
}
