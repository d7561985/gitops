import { InjectionToken } from '@angular/core';

export interface RTPMetrics {
  periodHours: number;
  overallRtp: number;
  rtpThreshold: {
    min: number;
    max: number;
    status: string;
  };
  gameCount: number;
  uniquePlayers: number;
  totalRevenue: number;
  totalPayouts: number;
}

export interface SessionMetrics {
  activeSessions: number;
  avgDuration: number;
}

export interface FinancialMetrics {
  periodHours: number;
  totalRevenue: number;
  depositCount: number;
  avgDeposit: number;
  withdrawalCount: number;
  avgWithdrawal: number;
}

export interface IAnalyticsService {
  getRTPMetrics(hours: number): Promise<RTPMetrics>;
  getSessionMetrics(): Promise<SessionMetrics>;
  getFinancialMetrics(hours: number): Promise<FinancialMetrics>;
}

export const ANALYTICS_SERVICE = new InjectionToken<IAnalyticsService>('AnalyticsService');
