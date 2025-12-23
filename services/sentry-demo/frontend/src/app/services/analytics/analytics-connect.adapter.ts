import { Injectable } from '@angular/core';
import { createClient, type Client } from '@connectrpc/connect';
import { createConnectTransport } from '@connectrpc/connect-web';
import { AnalyticsService } from '@gitops-poc-dzha/analytics-service-web/analytics/v1/analytics_pb';
import { environment } from '../../../environments/environment';
import { IAnalyticsService, RTPMetrics, SessionMetrics, FinancialMetrics } from './analytics.port';

@Injectable()
export class AnalyticsConnectAdapter implements IAnalyticsService {
  private readonly client: Client<typeof AnalyticsService>;

  constructor() {
    const transport = createConnectTransport({
      baseUrl: (environment.apiUrl || '') + '/api/analytics',
    });
    this.client = createClient(AnalyticsService, transport);
  }

  async getRTPMetrics(hours: number): Promise<RTPMetrics> {
    const response = await this.client.getRTPMetrics({ hours });

    return {
      periodHours: response.periodHours,
      overallRtp: response.overallRtp,
      rtpThreshold: {
        min: response.rtpThreshold?.min ?? 92,
        max: response.rtpThreshold?.max ?? 96,
        status: response.rtpThreshold?.status ?? 'normal',
      },
      gameCount: response.gameCount,
      uniquePlayers: response.uniquePlayers,
      totalRevenue: response.totalRevenue,
      totalPayouts: response.totalPayouts,
    };
  }

  async getSessionMetrics(): Promise<SessionMetrics> {
    const response = await this.client.getSessionMetrics({});

    return {
      activeSessions: response.activeSessions,
      avgDuration: response.avgDuration,
    };
  }

  async getFinancialMetrics(hours: number): Promise<FinancialMetrics> {
    const response = await this.client.getFinancialMetrics({ hours });

    return {
      periodHours: response.periodHours,
      totalRevenue: response.totalRevenue,
      depositCount: response.depositCount,
      avgDeposit: response.avgDeposit,
      withdrawalCount: response.withdrawalCount,
      avgWithdrawal: response.avgWithdrawal,
    };
  }
}
