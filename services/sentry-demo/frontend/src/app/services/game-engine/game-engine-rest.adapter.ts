import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../../environments/environment';
import { IGameEngineService, SpinResult, BusinessMetricsResult } from './game-engine.port';

/**
 * REST Adapter for Game Engine Service
 * Uses HTTP/JSON via Angular HttpClient
 */
@Injectable()
export class GameEngineRestAdapter implements IGameEngineService {
  private readonly baseUrl = (environment.apiUrl || '') + '/api/game';

  constructor(private http: HttpClient) {}

  async calculate(userId: string, bet: number, cpuIntensive = false): Promise<SpinResult> {
    const response = await firstValueFrom(
      this.http.post<any>(`${this.baseUrl}/calculate`, {
        userId,
        bet,
        cpu_intensive: cpuIntensive,
      })
    );

    return {
      win: response.win,
      payout: response.payout,
      newBalance: response.newBalance,
      symbols: response.symbols || [],
      wageringProgress: response.wageringProgress ? {
        progressPercent: response.wageringProgress.progress_percent || response.wageringProgress.progressPercent,
        remaining: response.wageringProgress.remaining,
        canConvert: response.wageringProgress.can_convert || response.wageringProgress.canConvert,
      } : undefined,
    };
  }

  async trackBusinessMetrics(scenario: string): Promise<BusinessMetricsResult> {
    const response = await firstValueFrom(
      this.http.post<any>(`${this.baseUrl}/business-metrics`, { scenario })
    );

    return {
      status: response.status || 'ok',
    };
  }
}
