import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../../environments/environment';
import { IWagerService, ValidationResult, ValidationData, PlaceResult, WagerHistoryResult } from './wager.port';

/**
 * REST Adapter for Wager Service
 * Uses HTTP/JSON via Angular HttpClient
 */
@Injectable()
export class WagerRestAdapter implements IWagerService {
  private readonly baseUrl = (environment.apiUrl || '') + '/api/wager';

  constructor(private http: HttpClient) {}

  async validate(userId: string, amount: number, gameId: string): Promise<ValidationResult> {
    const response = await firstValueFrom(
      this.http.post<any>(`${this.baseUrl}/validate`, {
        user_id: userId,
        amount,
        game_id: gameId,
      })
    );

    return {
      valid: response.valid,
      validationToken: response.validation_token,
      bonusUsed: response.bonus_used,
      realUsed: response.real_used,
      userId: response.user_id,
      amount: response.amount,
      gameId: response.game_id,
    };
  }

  async place(validationData: ValidationData, gameResult: 'win' | 'lose', payout: number): Promise<PlaceResult> {
    const response = await firstValueFrom(
      this.http.post<any>(`${this.baseUrl}/place`, {
        validation_data: {
          user_id: validationData.userId,
          amount: validationData.amount,
          game_id: validationData.gameId,
          bonus_used: validationData.bonusUsed,
          real_used: validationData.realUsed,
          validation_token: validationData.validationToken,
        },
        game_result: gameResult,
        payout,
      })
    );

    return {
      wagerId: response.wager_id,
      success: response.success,
      wageringProgress: response.wagering_progress ? {
        progressPercent: response.wagering_progress.progress_percent,
        remaining: response.wagering_progress.remaining,
        canConvert: response.wagering_progress.can_convert,
        totalRequired: response.wagering_progress.total_required,
        totalWagered: response.wagering_progress.total_wagered,
      } : undefined,
    };
  }

  async getHistory(userId: string, limit = 20): Promise<WagerHistoryResult> {
    const response = await firstValueFrom(
      this.http.get<any>(`${this.baseUrl}/history/${userId}`, {
        params: { limit: limit.toString() },
      })
    );

    return {
      wagers: (response.wagers || []).map((w: any) => ({
        wagerId: w.wager_id,
        userId: w.user_id,
        gameId: w.game_id,
        amount: w.amount,
        gameResult: w.game_result,
        payout: w.payout,
        bonusUsed: w.bonus_used,
        realUsed: w.real_used,
        createdAt: w.created_at,
      })),
      totalCount: response.total_count,
    };
  }
}
