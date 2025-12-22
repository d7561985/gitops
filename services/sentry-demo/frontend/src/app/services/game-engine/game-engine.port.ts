/**
 * Game Engine Service Port (Interface)
 * Clean Architecture - defines contract for game operations
 */

export interface SpinResult {
  win: boolean;
  payout: number;
  newBalance: number;
  symbols: string[];
  wageringProgress?: {
    progressPercent: number;
    remaining: number;
    canConvert: boolean;
  };
}

export interface BusinessMetricsResult {
  status: string;
}

/**
 * IGameEngineService - Port interface for game engine operations
 * Implementations: REST adapter, Connect adapter
 */
export interface IGameEngineService {
  calculate(userId: string, bet: number, cpuIntensive?: boolean): Promise<SpinResult>;
  trackBusinessMetrics(scenario: string): Promise<BusinessMetricsResult>;
}

/**
 * Injection token for IGameEngineService
 */
export const GAME_ENGINE_SERVICE = 'IGameEngineService';
