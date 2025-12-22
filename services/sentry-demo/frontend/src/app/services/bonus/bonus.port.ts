/**
 * Bonus Service Port (Interface)
 * Clean Architecture - defines contract for bonus operations
 */

export interface BonusProgress {
  hasActiveBonus: boolean;
  bonus?: {
    id: string;
    type: string;
    amount: number;
    wageringRequired: number;
    wageringCompleted: number;
    progressPercent: number;
    status: string;
    expiresAt: string;
  };
  balance: {
    real: number;
    bonus: number;
    total: number;
  };
}

export interface ClaimResult {
  success: boolean;
  bonusId: string;
  amount: number;
  wageringRequired: number;
  error?: string;
}

export interface ConvertResult {
  success: boolean;
  convertedAmount: number;
  newBalance: number;
  error?: string;
}

/**
 * IBonusService - Port interface for bonus operations
 * Implementations: REST adapter, Connect adapter
 */
export interface IBonusService {
  getProgress(userId: string): Promise<BonusProgress>;
  claim(userId: string): Promise<ClaimResult>;
  convert(userId: string): Promise<ConvertResult>;
}

/**
 * Injection token for IBonusService
 */
export const BONUS_SERVICE = 'IBonusService';
