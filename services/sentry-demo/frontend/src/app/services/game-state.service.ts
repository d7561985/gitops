import { Injectable, signal, computed } from '@angular/core';

interface SpinResult {
  win: boolean;
  payout: number;
  symbols: string[];
  winAmount: number;
  betAmount: number;
  newBalance: number;
}

@Injectable({ providedIn: 'root' })
export class GameStateService {
  // State signals
  private _balance = signal(1000);
  private _isSpinning = signal(false);
  private _spinHistory = signal<SpinResult[]>([]);
  private _lastResult = signal<SpinResult | null>(null);
  
  // Public readonly signals
  balance = this._balance.asReadonly();
  isSpinning = this._isSpinning.asReadonly();
  spinHistory = this._spinHistory.asReadonly();
  lastResult = this._lastResult.asReadonly();
  
  // Computed signals
  totalWinnings = computed(() => 
    this._spinHistory().reduce((sum, spin) => sum + (spin.payout - spin.betAmount), 0)
  );
  
  totalSpins = computed(() => this._spinHistory().length);
  
  winRate = computed(() => {
    const history = this._spinHistory();
    if (history.length === 0) return 0;
    const wins = history.filter(s => s.win).length;
    return (wins / history.length) * 100;
  });
  
  avgPayout = computed(() => {
    const history = this._spinHistory();
    if (history.length === 0) return 0;
    const totalPayout = history.reduce((sum, spin) => sum + spin.payout, 0);
    return totalPayout / history.length;
  });
  
  // State mutations
  updateBalance(amount: number) {
    this._balance.set(amount);
  }
  
  startSpin() {
    this._isSpinning.set(true);
  }
  
  completeSpin(result: SpinResult) {
    this._isSpinning.set(false);
    this._lastResult.set(result);
    this._spinHistory.update(history => [...history, result]);
    this._balance.set(result.newBalance);
  }
  
  resetHistory() {
    this._spinHistory.set([]);
  }
}