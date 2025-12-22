/**
 * Wager Service Port (Interface)
 * Clean Architecture - defines contract for wager operations
 */

export interface ValidationResult {
  valid: boolean;
  validationToken: string;
  bonusUsed: number;
  realUsed: number;
  userId: string;
  amount: number;
  gameId: string;
}

export interface ValidationData {
  userId: string;
  amount: number;
  gameId: string;
  bonusUsed: number;
  realUsed: number;
  validationToken: string;
}

export interface WageringProgress {
  progressPercent: number;
  remaining: number;
  canConvert: boolean;
  totalRequired: number;
  totalWagered: number;
}

export interface PlaceResult {
  wagerId: string;
  success: boolean;
  wageringProgress?: WageringProgress;
}

export interface WagerRecord {
  wagerId: string;
  userId: string;
  gameId: string;
  amount: number;
  gameResult: string;
  payout: number;
  bonusUsed: number;
  realUsed: number;
  createdAt: string;
}

export interface WagerHistoryResult {
  wagers: WagerRecord[];
  totalCount: number;
}

/**
 * IWagerService - Port interface for wager operations
 * Implementations: REST adapter, Connect adapter
 */
export interface IWagerService {
  validate(userId: string, amount: number, gameId: string): Promise<ValidationResult>;
  place(validationData: ValidationData, gameResult: 'win' | 'lose', payout: number): Promise<PlaceResult>;
  getHistory(userId: string, limit?: number): Promise<WagerHistoryResult>;
}

/**
 * Injection token for IWagerService
 */
export const WAGER_SERVICE = 'IWagerService';
