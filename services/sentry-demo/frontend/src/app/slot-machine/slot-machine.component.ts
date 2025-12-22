// Version is injected at build time via APP_VERSION build arg
import { Component, OnInit, Inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import * as Sentry from '@sentry/angular';
import { GameStateService } from '../services/game-state.service';
import { BonusTrackerComponent } from '../components/bonus-tracker.component';
import { BonusRefreshService } from '../services/bonus-refresh.service';
import {
  createNewTrace,
  TransactionNames,
  Operations,
  setTransactionStatus
} from '../utils/sentry-traces';
import { environment } from '../../environments/environment';
// Clean Architecture: Protocol-agnostic service injection
import { GAME_ENGINE_SERVICE, IGameEngineService } from '../services/game-engine';

@Component({
    selector: 'app-slot-machine',
    standalone: true,
    imports: [CommonModule, BonusTrackerComponent],
    template: `
    <div class="slot-machine">
      <h2>🎰 Simple Slot Machine</h2>
      <div class="version">v{{version}}</div>
    
      <div class="balance">
        Balance: $<span>{{balance()}}</span>
      </div>
      
      <!-- Bonus Tracker Component -->
      <app-bonus-tracker></app-bonus-tracker>
      
      <!-- Statistics Panel -->
      @if (totalSpins() > 0) {
        <div class="stats-panel">
          <div class="stat">
            <span class="stat-label">Total Spins:</span>
            <span class="stat-value">{{totalSpins()}}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Win Rate:</span>
            <span class="stat-value">{{winRate().toFixed(1)}}%</span>
          </div>
        </div>
      }
    
      <!-- 3 Reels in a Row -->
      <div class="slots-container">
        @for (reel of reels; track i; let i = $index) {
          <div class="slot-window">
            <div class="reel" [class.spinning]="isSpinning()">
              @if (isSpinning()) {
                <div class="symbol-strip">
                  @for (symbol of spinningSymbols; track symbol.id) {
                    <div class="symbol">{{ symbol.value }}</div>
                  }
                  <!-- Duplicate symbols for seamless loop -->
                  @for (symbol of spinningSymbols; track symbol.id + 100) {
                    <div class="symbol">{{ symbol.value }}</div>
                  }
                </div>
              }
              @if (!isSpinning()) {
                <div class="symbol static">{{ reel }}</div>
              }
            </div>
          </div>
        }
      </div>
    
      <button
        class="spin-button"
        (click)="spin()"
        [disabled]="isSpinning() || balance() < 10">
        {{ isSpinning() ? 'Spinning...' : 'SPIN ($10)' }}
      </button>
    
      @if (lastResult() && !isSpinning()) {
        <div class="result">
          @if (lastResult()!.win) {
            <div class="win">
              🎉 You won $<span>{{lastResult()!.payout}}</span>!
            </div>
          }
          @if (!lastResult()!.win) {
            <div class="lose">
              Better luck next time!
            </div>
          }
        </div>
      }
    
      @if (error) {
        <div class="error">
          ❌ Error: {{ error }}
        </div>
      }
    
      <div style="margin-top: 40px; opacity: 0.7;">
        <small>User ID: {{ userId }}</small>
      </div>
    </div>
    `,
    styles: [`
    .slot-machine {
      text-align: center;
      padding: 20px;
      max-width: 600px;
      margin: 0 auto;
    }

    .version {
      font-size: 12px;
      color: #666;
      margin-top: -10px;
      margin-bottom: 10px;
    }

    .balance {
      font-size: 24px;
      margin-bottom: 30px;
      color: #4CAF50;
    }

    .slots-container {
      display: flex;
      justify-content: center;
      gap: 10px;
      margin: 0 auto 30px;
    }

    .slot-window {
      width: 120px;
      height: 120px;
      background: #2a2a2a;
      border: 5px solid #444;
      border-radius: 15px;
      overflow: hidden;
      position: relative;
      box-shadow: 
        inset 0 0 20px rgba(0,0,0,0.5),
        0 0 20px rgba(255,255,255,0.1);
    }

    .reel {
      height: 100%;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .symbol-strip {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
    }

    .reel.spinning .symbol-strip {
      animation: scroll 0.8s linear infinite;
    }

    @keyframes scroll {
      0% {
        transform: translateY(-720px); /* Start above viewport */
      }
      100% {
        transform: translateY(0); /* Move down to original position */
      }
    }

    .symbol {
      font-size: 80px;
      height: 120px;
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
    }

    .symbol.static {
      position: absolute;
      top: 0;
      left: 0;
    }

    .spin-button {
      background: #FF6B6B;
      color: white;
      border: none;
      padding: 15px 40px;
      font-size: 20px;
      font-weight: bold;
      border-radius: 10px;
      cursor: pointer;
      transition: all 0.3s;
      box-shadow: 0 4px 15px rgba(255, 107, 107, 0.4);
    }

    .spin-button:hover:not(:disabled) {
      background: #FF5252;
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(255, 107, 107, 0.5);
    }

    .spin-button:disabled {
      background: #666;
      cursor: not-allowed;
      box-shadow: none;
    }

    .result {
      margin-top: 20px;
      font-size: 18px;
      font-weight: bold;
      min-height: 30px;
    }

    .result .win {
      color: #4CAF50;
      animation: pulse 0.5s ease-in-out 2;
    }

    .result .lose {
      color: #999;
    }

    @keyframes pulse {
      0%, 100% {
        transform: scale(1);
      }
      50% {
        transform: scale(1.1);
      }
    }

    .error {
      color: #F44336;
      margin-top: 10px;
    }

    /* Stats Panel Styles */
    .stats-panel {
      background: #2a2a2a;
      border: 1px solid #444;
      border-radius: 10px;
      padding: 15px;
      margin-bottom: 20px;
      display: flex;
      justify-content: space-around;
      gap: 20px;
    }

    .stat {
      text-align: center;
    }

    .stat-label {
      display: block;
      font-size: 14px;
      color: #999;
      margin-bottom: 5px;
    }

    .stat-value {
      display: block;
      font-size: 20px;
      font-weight: bold;
      color: #4CAF50;
    }
  `]
})
export class SlotMachineComponent implements OnInit {
  // Component state
  error: string | null = null;
  userId = 'demo-user-' + Math.floor(Math.random() * 1000);
  reels: string[] = ['🍒', '🍋', '🍊'];
  spinningSymbols = [
    { id: 0, value: '🍒' },
    { id: 1, value: '🍋' },
    { id: 2, value: '🍊' },
    { id: 3, value: '🍇' },
    { id: 4, value: '⭐' },
    { id: 5, value: '💎' }
  ];
  
  // Debug panel properties
  debugPanelOpen = false;
  debugStatus: string | null = null;
  
  // Signals from state service
  balance = this.gameState.balance;
  isSpinning = this.gameState.isSpinning;
  lastResult = this.gameState.lastResult;
  winRate = this.gameState.winRate;
  totalSpins = this.gameState.totalSpins;
  version = environment.version;

  constructor(
    @Inject(GAME_ENGINE_SERVICE) private gameService: IGameEngineService,
    private gameState: GameStateService,
    private http: HttpClient,
    private bonusRefreshService: BonusRefreshService
  ) {}

  get apiUrl(): string {
    return (environment.apiUrl || '') + '/api/game';
  }

  ngOnInit(): void {
    // Save userId to localStorage for other components
    localStorage.setItem('userId', this.userId);
    
    // Set user context for Sentry
    Sentry.setUser({
      id: this.userId,
      username: 'demo_player'
    });
  }

  async spin(): Promise<void> {
    this.error = null;
    
    // Start the spinning animation
    this.gameState.startSpin();
    
    // Create an independent transaction for the spin action
    await createNewTrace(
      TransactionNames.SLOT_SPIN,
      Operations.USER_ACTION,
      async (span) => {
        try {
          // Add user context attributes
          span?.setAttribute('user.id', this.userId);
          span?.setAttribute('bet.amount', 10);
          span?.setAttribute('balance.before', this.balance());
          
          const result = await this.gameService.calculate(this.userId, 10);
          if (result) {
            // Log spin result
            console.log('Spin completed', {
              win: result.win,
              payout: result.payout,
              symbols: result.symbols,
              newBalance: result.newBalance
            });
            
            // Add custom context
            span?.setAttribute('win', result.win);
            span?.setAttribute('payout', result.payout);
            span?.setAttribute('balance.after', result.newBalance);
        
            // Show the result symbols immediately
            if (result.symbols && result.symbols.length > 0) {
              this.reels = [
                result.symbols[0] || '🍒',
                result.symbols[1] || result.symbols[0] || '🍒',
                result.symbols[2] || result.symbols[0] || '🍒'
              ];
            }
            
            // Short animation to show final result (just one more spin cycle)
            await new Promise<void>(resolve => {
              setTimeout(() => {
                // Update state through service
                this.gameState.completeSpin({
                  win: result.win,
                  payout: result.payout,
                  symbols: result.symbols || [],
                  winAmount: result.payout,
                  betAmount: 10,
                  newBalance: result.newBalance
                });
                
                // Trigger bonus refresh after successful spin
                this.bonusRefreshService.triggerRefresh();
                
                resolve();
              }, 800); // One animation cycle (matching CSS animation duration)
            });
            
            setTransactionStatus(span, true);
          }
        } catch (error: any) {
          this.error = error.message || 'Something went wrong!';
          // Stop the spinning animation on error
          this.gameState.completeSpin({
            win: false,
            payout: 0,
            symbols: [],
            winAmount: 0,
            betAmount: 10,
            newBalance: this.balance()
          });
          
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }
  
  // Debug Panel Methods for Error Scenarios
  
  async triggerPromiseRejection(): Promise<void> {
    this.debugStatus = 'Triggering unhandled promise rejection...';
    
    await createNewTrace(
      TransactionNames.SLOT_DEBUG_PROMISE,
      Operations.DEBUG,
      async (span) => {
        span?.setAttribute('debug.type', 'promise-rejection');
        
        // Create a promise that will reject after 1 second
        // NOT catching this error intentionally to demonstrate unhandled rejection
        setTimeout(() => {
          // This promise rejection will be unhandled
          Promise.reject(new Error('Unhandled promise rejection from debug panel'));
          this.debugStatus = 'Promise rejection triggered! Check Sentry dashboard.';
        }, 1000);
        
        // Mark transaction as complete before the rejection happens
        setTransactionStatus(span, true);
      }
    );
  }
  
  async triggerComponentError(): Promise<void> {
    this.debugStatus = 'Triggering component error...';
    
    await createNewTrace(
      TransactionNames.SLOT_DEBUG_ERROR,
      Operations.DEBUG,
      async (span) => {
        span?.setAttribute('debug.type', 'component-error');
        
        // Intentionally throw an error to be caught by Angular ErrorHandler
        setTimeout(() => {
          throw new Error('Component error triggered from debug panel');
        }, 100);
        
        // Mark transaction as complete before the error is thrown
        setTransactionStatus(span, true);
      }
    );
  }
  
  async triggerGatewayPanic(): Promise<void> {
    this.debugStatus = 'Triggering gateway panic...';
    
    await createNewTrace(
      TransactionNames.SLOT_DEBUG_PANIC,
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'gateway-panic');
          
          // Use special userId that triggers panic in gateway
          // Using HttpClient for proper trace propagation
          try {
            await firstValueFrom(this.http.get(`${this.apiUrl}/api/game/debug/panic/panic-test`));
          } catch (httpError) {
            // Expected to fail when gateway panics
            this.debugStatus = 'Gateway panic triggered! Check Sentry for Go panic.';
          }
          setTransactionStatus(span, true);
        } catch (error: any) {
          this.debugStatus = 'Gateway panic triggered (connection lost)';
          // This is expected when gateway panics
          setTransactionStatus(span, true);
        }
      }
    );
  }
  
  async triggerAuthError(): Promise<void> {
    this.debugStatus = 'Triggering 401 auth error...';
    
    await createNewTrace(
      TransactionNames.SLOT_DEBUG_AUTH,
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'auth-error');
          span?.setAttribute('user.id', this.userId);
          
          // Call user service with invalid token
          // Using HttpClient for proper trace propagation
          try {
            await firstValueFrom(this.http.get(`${this.apiUrl}/api/game/user/${this.userId}`, {
              headers: {
                'Authorization': 'Bearer invalid-token'
              }
            }));
            this.debugStatus = `Unexpected response - no error`;
          } catch (error: any) {
            if (error.status === 401) {
              this.debugStatus = '401 Auth error triggered! Check Sentry dashboard.';
              span?.setAttribute('http.status_code', 401);
            } else {
              this.debugStatus = `Unexpected response: ${error.status}`;
              span?.setAttribute('http.status_code', error.status);
            }
          }
          setTransactionStatus(span, true); // Debug triggers are successful even with 401
        } catch (error: any) {
          this.debugStatus = 'Error calling user service';
          setTransactionStatus(span, false, error);
        }
      }
    );
  }
  
  // Performance Issue Triggers
  
  async triggerN1Query(): Promise<void> {
    this.debugStatus = 'Triggering N+1 query problem...';
    
    await createNewTrace(
      TransactionNames.SLOT_DEBUG_N1,
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'n1-query');
          span?.setAttribute('user.id', this.userId);
          
          // Using HttpClient for proper trace propagation
          const data = await firstValueFrom(this.http.get<any>(`${this.apiUrl}/api/game/user/${this.userId}/history`));
          
          if (data) {
            this.debugStatus = `N+1 query executed! Found ${data.totalGames} games. Check Performance in Sentry.`;
            span?.setAttribute('games.count', data.totalGames);
            setTransactionStatus(span, true);
          }
        } catch (error: any) {
          if (error.status) {
            this.debugStatus = `Failed to trigger N+1: ${error.status}`;
          } else {
            this.debugStatus = 'Error triggering N+1 query';
          }
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }

  async triggerEnhancedN1Query(): Promise<void> {
    this.debugStatus = 'Triggering enhanced N+1 query (analytics)...';
    
    await createNewTrace(
      'user-action.debug.enhanced-n1-query',
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'enhanced-n1-query');
          span?.setAttribute('performance.issue', 'n+1_queries');
          
          // Using HttpClient for proper trace propagation
          const data = await firstValueFrom(this.http.get<any>(`${this.apiUrl}/api/game/analytics/player-details-n1`));
          
          if (data) {
            this.debugStatus = `Enhanced N+1 executed! ${data.queries_executed.total} queries for ${data.player_count} players. Check Performance → Analytics in Sentry.`;
            span?.setAttribute('queries.total', data.queries_executed.total);
            span?.setAttribute('players.count', data.player_count);
            span?.setAttribute('performance.warning', data.performance_warning);
            setTransactionStatus(span, true);
          }
        } catch (error: any) {
          if (error.status) {
            this.debugStatus = `Failed to trigger enhanced N+1: ${error.status}`;
          } else {
            this.debugStatus = 'Error triggering enhanced N+1 query';
          }
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }
  
  async triggerCPUSpike(): Promise<void> {
    this.debugStatus = 'Triggering CPU spike in game engine...';
    
    await createNewTrace(
      TransactionNames.SLOT_DEBUG_CPU,
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'cpu-spike');
          span?.setAttribute('user.id', this.userId);
          
          // Make a spin request with cpu_intensive flag
          // Using HttpClient for proper trace propagation
          await firstValueFrom(this.http.post(`${this.apiUrl}/api/game/calculate`, {
            userId: this.userId,
            bet: 10,
            cpu_intensive: true  // This triggers the CPU spike
          }));
          
          this.debugStatus = 'CPU spike completed! Check Performance → Game Engine in Sentry.';
          setTransactionStatus(span, true);
        } catch (error: any) {
          this.debugStatus = 'Error triggering CPU spike';
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }
  
  async triggerSlowAggregation(): Promise<void> {
    this.debugStatus = 'Triggering slow MongoDB aggregation...';
    
    await createNewTrace(
      TransactionNames.SLOT_DEBUG_AGGREGATION,
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'slow-aggregation');
          span?.setAttribute('days.requested', 30);
          
          // Call analytics service for daily stats
          // Using HttpClient for proper trace propagation - use API gateway proxy
          const data = await firstValueFrom(this.http.get<any>(`${this.apiUrl}/api/game/analytics/daily-stats?days=30`));
          
          this.debugStatus = `Slow aggregation completed! Processed ${data.days_returned} days. Check Performance → Analytics in Sentry.`;
          span?.setAttribute('days.returned', data.days_returned);
          setTransactionStatus(span, true);
        } catch (error: any) {
          this.debugStatus = 'Error triggering slow aggregation - is analytics service running?';
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }
  
  // New crash demonstration methods
  async triggerPythonCrash(service: 'game-engine' | 'analytics'): Promise<void> {
    this.debugStatus = `Triggering ${service} crash...`;
    
    await createNewTrace(
      `debug-${service}-crash`,
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'service-crash');
          span?.setAttribute('service', service);
          
          let url: string;
          if (service === 'game-engine') {
            url = `${this.apiUrl}/api/game/debug/crash`;
          } else {
            url = `${this.apiUrl}/api/game/debug/crash`;  // analytics routes through game
          }
          
          await firstValueFrom(this.http.get(url));
          
          // This shouldn't reach if crash works
          this.debugStatus = `${service} crash should have occurred - check Sentry!`;
        } catch (error: any) {
          if (error.status === 500) {
            this.debugStatus = `${service} crashed successfully! Check Sentry for RuntimeError.`;
          } else {
            this.debugStatus = `Error triggering ${service} crash: ${error.message}`;
          }
          setTransactionStatus(span, false, error);
        }
      }
    );
  }
  
  async triggerNodeCrash(): Promise<void> {
    this.debugStatus = 'Triggering payment service crash...';
    
    await createNewTrace(
      'debug-payment-crash',
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'service-crash');
          span?.setAttribute('service', 'payment');
          
          await firstValueFrom(this.http.get(`${this.apiUrl}/api/payment/debug/crash`));
          
          this.debugStatus = 'Payment crash should have occurred - check Sentry!';
        } catch (error: any) {
          if (error.status === 500) {
            this.debugStatus = 'Payment service crashed! Check Sentry for Node.js error.';
          } else {
            this.debugStatus = `Error triggering payment crash: ${error.message}`;
          }
          setTransactionStatus(span, false, error);
        }
      }
    );
  }
  
  async triggerMemoryLeak(service: 'game-engine' | 'payment'): Promise<void> {
    this.debugStatus = `Creating memory leak in ${service}...`;
    
    await createNewTrace(
      `debug-${service}-memory-leak`,
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'memory-leak');
          span?.setAttribute('service', service);
          
          let url: string;
          if (service === 'game-engine') {
            url = `${this.apiUrl}/api/game/debug/memory-leak`;
          } else {
            url = `${this.apiUrl}/api/payment/debug/memory-leak`;
          }
          
          const response = await firstValueFrom(this.http.get<any>(url));
          
          this.debugStatus = `Memory leak created! ${response.total_leaked_mb || response.estimated_total_leak_mb}MB leaked. Check Sentry.`;
          span?.setAttribute('memory.leaked_mb', response.total_leaked_mb || response.estimated_total_leak_mb);
          setTransactionStatus(span, true);
        } catch (error: any) {
          this.debugStatus = `Error creating memory leak: ${error.message}`;
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }
  
  async triggerThreadingError(): Promise<void> {
    this.debugStatus = 'Triggering threading error in game engine...';
    
    await createNewTrace(
      'debug-threading-error',
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'threading-error');
          
          const response = await firstValueFrom(
            this.http.get<any>(`${this.apiUrl}/api/game/debug/threading-error`)
          );
          
          this.debugStatus = `Threading demo completed with ${response.threads_created} threads. Check Sentry!`;
          span?.setAttribute('threads.created', response.threads_created);
          setTransactionStatus(span, true);
        } catch (error: any) {
          this.debugStatus = `Error in threading demo: ${error.message}`;
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }
  
  async triggerValidationError(): Promise<void> {
    this.debugStatus = 'Triggering validation error in analytics...';
    
    await createNewTrace(
      'debug-validation-error',
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'validation-error');
          
          await firstValueFrom(
            this.http.get(`${this.apiUrl}/api/game/debug/validation-error`)
          );
          
          this.debugStatus = 'Validation error should have occurred - check Sentry!';
        } catch (error: any) {
          if (error.status === 422 || error.status === 500) {
            this.debugStatus = 'Validation error triggered! Check Sentry for Pydantic errors.';
          } else {
            this.debugStatus = `Error triggering validation: ${error.message}`;
          }
          setTransactionStatus(span, false, error);
        }
      }
    );
  }
  
  async triggerPromiseRejectionNode(): Promise<void> {
    this.debugStatus = 'Triggering unhandled promise rejection in payment service...';
    
    await createNewTrace(
      'debug-promise-rejection-node',
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'promise-rejection');
          
          const response = await firstValueFrom(
            this.http.get<any>(`${this.apiUrl}/api/payment/debug/promise-rejection`)
          );
          
          this.debugStatus = response.status || 'Promise rejection triggered - check Sentry!';
          setTransactionStatus(span, true);
        } catch (error: any) {
          this.debugStatus = `Error triggering promise rejection: ${error.message}`;
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }
  
  async triggerEventLoopBlock(): Promise<void> {
    this.debugStatus = 'Blocking event loop in payment service (3 seconds)...';
    
    await createNewTrace(
      'debug-event-loop-block',
      Operations.DEBUG,
      async (span) => {
        try {
          span?.setAttribute('debug.type', 'event-loop-block');
          
          const response = await firstValueFrom(
            this.http.get<any>(`${this.apiUrl}/api/payment/debug/event-loop-block`)
          );
          
          this.debugStatus = `Event loop blocked for ${response.duration_ms}ms! ${response.warning}`;
          span?.setAttribute('block.duration_ms', response.duration_ms);
          setTransactionStatus(span, true);
        } catch (error: any) {
          this.debugStatus = `Error blocking event loop: ${error.message}`;
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }

  demoConsoleLogs(): void {
    this.debugStatus = 'Sending demo logs to Sentry...';
    
    // Demo various console log levels - these will be captured as breadcrumbs
    console.log('This is a regular log message', { 
      userId: this.userId, 
      balance: this.balance() 
    });
    
    console.info('Info level: Game state information', {
      totalSpins: this.totalSpins(),
      winRate: this.winRate(),
      timestamp: new Date().toISOString()
    });
    
    console.debug('Debug data for developers', {
      component: 'SlotMachineComponent',
      version: this.version,
      apiUrl: this.apiUrl
    });
    
    console.warn('Warning: Low balance detected!', {
      currentBalance: this.balance(),
      minimumRequired: 10,
      userId: this.userId
    });
    
    console.error('Error: Demo error for testing (not a real error)', {
      errorCode: 'DEMO_ERROR',
      context: 'This is just for demonstration purposes',
      stack: new Error().stack
    });
    
    console.trace('Trace level logging with call stack');
    
    // Using Sentry Log API (experimental feature)
    const { logger } = Sentry;
    
    // Log with different severity levels using the new Log API
    logger.info('This is an info log using Sentry Log API', {
      userId: this.userId,
      component: 'SlotMachineComponent',
      action: 'demoLogs'
    });
    
    logger.warn('Warning: Player approaching minimum balance threshold', {
      currentBalance: this.balance(),
      threshold: 10,
      percentageRemaining: (this.balance() / 100) * 100
    });
    
    logger.debug('Debug information for developers', {
      version: this.version,
      apiEndpoint: this.apiUrl,
      browserInfo: navigator.userAgent,
      timestamp: new Date().toISOString()
    });
    
    logger.error('Error: Demo error using Log API (not a real error)', {
      errorCode: 'DEMO_LOG_ERROR',
      simulatedError: true,
      context: 'Testing Sentry Log API functionality'
    });
    
    logger.fatal('Fatal: Critical system failure simulation', {
      component: 'GameEngine',
      failureType: 'SIMULATED',
      recoverable: true
    });
    
    // Log with trace level
    logger.trace('Trace level: Detailed execution flow', {
      method: 'demoConsoleLogs',
      callStack: new Error().stack,
      executionTime: Date.now()
    });
    
    // Adding breadcrumbs for additional context
    Sentry.addBreadcrumb({
      message: 'User triggered demo logs',
      level: 'info',
      category: 'demo',
      data: {
        userId: this.userId,
        action: 'demoConsoleLogs'
      }
    });
    
    Sentry.addBreadcrumb({
      message: 'Game state snapshot',
      level: 'info',
      category: 'game',
      type: 'info',
      data: {
        balance: this.balance(),
        totalSpins: this.totalSpins(),
        winRate: this.winRate()
      }
    });
    
    // Set context for better log organization
    Sentry.setContext('game_state', {
      balance: this.balance(),
      totalSpins: this.totalSpins(),
      winRate: this.winRate(),
      lastResult: this.lastResult()
    });
    
    // Set tags for filtering
    Sentry.setTags({
      demo_type: 'logging_api',
      user_id: this.userId,
      uses_experimental_logs: true
    });
    
    // Also demonstrate structured logging with extra data
    logger.info('Structured game event with rich metadata', {
      event: 'demo_logging_test',
      player: {
        id: this.userId,
        type: 'demo_user',
        sessionLength: Date.now()
      },
      gameState: {
        balance: this.balance(),
        totalSpins: this.totalSpins(),
        winRate: this.winRate(),
        recentResults: this.lastResult()
      },
      systemInfo: {
        version: this.version,
        environment: environment.production ? 'production' : 'development',
        timestamp: new Date().toISOString()
      }
    });
    
    setTimeout(() => {
      this.debugStatus = 'Logs sent! Check Sentry Logs (experimental) for structured log entries and console breadcrumbs.';
    }, 1000);
  }
}