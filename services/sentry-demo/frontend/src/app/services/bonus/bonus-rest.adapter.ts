import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../../environments/environment';
import { IBonusService, BonusProgress, ClaimResult, ConvertResult } from './bonus.port';

/**
 * REST Adapter for Bonus Service
 * Uses HTTP/JSON via Angular HttpClient
 */
@Injectable()
export class BonusRestAdapter implements IBonusService {
  private readonly baseUrl = (environment.apiUrl || '') + '/api/bonus';

  constructor(private http: HttpClient) {}

  async getProgress(userId: string): Promise<BonusProgress> {
    const response = await firstValueFrom(
      this.http.get<any>(`${this.baseUrl}/progress/${userId}`)
    );

    return {
      hasActiveBonus: response.has_active_bonus,
      bonus: response.bonus ? {
        id: response.bonus.id,
        type: response.bonus.type,
        amount: response.bonus.amount,
        wageringRequired: response.bonus.wagering_required,
        wageringCompleted: response.bonus.wagering_completed,
        progressPercent: response.bonus.progress_percentage,
        status: response.bonus.status,
        expiresAt: response.bonus.expires_at || '',
      } : undefined,
      balance: {
        real: response.balance.real,
        bonus: response.balance.bonus,
        total: response.balance.total,
      },
    };
  }

  async claim(userId: string): Promise<ClaimResult> {
    const response = await firstValueFrom(
      this.http.post<any>(`${this.baseUrl}/claim`, {
        user_id: userId,
        bonus_type: 'WELCOME',
        amount: 100,
        multiplier: 30,
      })
    );

    return {
      success: true,
      bonusId: response.bonus_id || '',
      amount: response.amount || 100,
      wageringRequired: response.wagering_required || 3000,
    };
  }

  async convert(userId: string): Promise<ConvertResult> {
    const response = await firstValueFrom(
      this.http.post<any>(`${this.baseUrl}/convert/${userId}`, {})
    );

    return {
      success: true,
      convertedAmount: response.converted_amount || 0,
      newBalance: response.new_balance || 0,
    };
  }
}
