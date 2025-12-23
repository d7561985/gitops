import { Component, OnInit, OnDestroy, Inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { interval, Subscription } from 'rxjs';
import * as Sentry from '@sentry/angular';
import {
  createNewTrace,
  TransactionNames,
  Operations,
  setTransactionStatus
} from '../utils/sentry-traces';
import {
  ANALYTICS_SERVICE,
  IAnalyticsService,
  RTPMetrics,
  SessionMetrics,
  FinancialMetrics
} from '../services/analytics';

@Component({
    selector: 'app-business-metrics',
    standalone: true,
    imports: [CommonModule],
    template: `
    <div class="metrics-dashboard">
      <h2>Business Metrics Dashboard</h2>

      <div class="metrics-grid">
        <!-- RTP Metric Card -->
        <div class="metric-card" [class.anomaly]="rtpData?.rtpThreshold?.status === 'anomaly'">
          <h3>Return to Player (RTP)</h3>
          <div class="metric-value">{{ rtpData?.overallRtp?.toFixed(2) || '0.00' }}%</div>
          <div class="metric-status" [class.warning]="rtpData?.rtpThreshold?.status === 'anomaly'">
            {{ rtpData?.rtpThreshold?.status === 'anomaly' ? 'Anomaly Detected' : 'Normal' }}
          </div>
          <div class="metric-range">Expected: {{ rtpData?.rtpThreshold?.min }}-{{ rtpData?.rtpThreshold?.max }}%</div>
        </div>

        <!-- Session Metrics Card -->
        <div class="metric-card">
          <h3>Active Sessions</h3>
          <div class="metric-value">{{ sessionData?.activeSessions || 0 }}</div>
          <div class="metric-subtext">Avg Duration: {{ sessionData?.avgDuration?.toFixed(0) || 0 }}s</div>
        </div>

        <!-- Financial Metrics Card -->
        <div class="metric-card">
          <h3>Financial Overview (24h)</h3>
          <div class="metric-row">
            <span>Revenue:</span>
            <span class="value">{{ '$' + (financialData?.totalRevenue?.toFixed(2) || '0.00') }}</span>
          </div>
          <div class="metric-row">
            <span>Deposits:</span>
            <span class="value">{{ financialData?.depositCount || 0 }} ({{ '$' + (financialData?.avgDeposit?.toFixed(2) || '0.00') }} avg)</span>
          </div>
          <div class="metric-row">
            <span>Withdrawals:</span>
            <span class="value">{{ financialData?.withdrawalCount || 0 }} ({{ '$' + (financialData?.avgWithdrawal?.toFixed(2) || '0.00') }} avg)</span>
          </div>
        </div>

        <!-- Game Activity Card -->
        <div class="metric-card">
          <h3>Game Activity</h3>
          <div class="metric-value">{{ rtpData?.gameCount || 0 }}</div>
          <div class="metric-subtext">Games in last hour</div>
          <div class="metric-subtext">{{ rtpData?.uniquePlayers || 0 }} unique players</div>
        </div>
      </div>

      <div class="refresh-info">
        Auto-refreshing every 10 seconds
        <span class="status" [class.error]="hasError">{{ hasError ? 'Error' : 'Connected' }}</span>
      </div>

      @if (errorMessage) {
        <div class="error-message">
          {{ errorMessage }}
        </div>
      }
    </div>
    `,
    styles: [`
    .metrics-dashboard {
      padding: 20px;
      max-width: 1200px;
      margin: 0 auto;
    }

    h2 {
      text-align: center;
      margin-bottom: 30px;
      color: #4CAF50;
    }

    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 20px;
      margin-bottom: 20px;
    }

    .metric-card {
      background: #2a2a2a;
      border: 2px solid #444;
      border-radius: 10px;
      padding: 20px;
      transition: all 0.3s;
    }

    .metric-card.anomaly {
      border-color: #ff9800;
      background: #3a2a2a;
    }

    .metric-card h3 {
      margin: 0 0 15px 0;
      color: #4CAF50;
      font-size: 18px;
    }

    .metric-value {
      font-size: 36px;
      font-weight: bold;
      color: #fff;
      margin: 10px 0;
    }

    .metric-status {
      font-size: 14px;
      color: #4CAF50;
      margin: 10px 0;
    }

    .metric-status.warning {
      color: #ff9800;
    }

    .metric-range {
      font-size: 12px;
      color: #999;
    }

    .metric-subtext {
      font-size: 14px;
      color: #ccc;
      margin: 5px 0;
    }

    .metric-row {
      display: flex;
      justify-content: space-between;
      margin: 8px 0;
      font-size: 14px;
    }

    .metric-row .value {
      color: #4CAF50;
      font-weight: bold;
    }

    .refresh-info {
      text-align: center;
      color: #999;
      font-size: 14px;
      margin-top: 20px;
    }

    .status {
      margin-left: 10px;
    }

    .status.error {
      color: #f44336;
    }

    .error-message {
      background: #f44336;
      color: white;
      padding: 10px;
      border-radius: 5px;
      margin-top: 20px;
      text-align: center;
    }
  `]
})
export class BusinessMetricsComponent implements OnInit, OnDestroy {
  rtpData: RTPMetrics | null = null;
  sessionData: SessionMetrics | null = null;
  financialData: FinancialMetrics | null = null;
  hasError = false;
  errorMessage = '';

  private refreshSubscription?: Subscription;

  constructor(@Inject(ANALYTICS_SERVICE) private analyticsService: IAnalyticsService) {}

  ngOnInit(): void {
    this.loadMetrics();
    this.refreshSubscription = interval(10000).subscribe(() => {
      this.loadMetrics();
    });
  }

  ngOnDestroy(): void {
    if (this.refreshSubscription) {
      this.refreshSubscription.unsubscribe();
    }
  }

  private async loadMetrics(): Promise<void> {
    await createNewTrace(
      TransactionNames.METRICS_REFRESH,
      Operations.USER_ACTION,
      async (span) => {
        try {
          span?.setAttribute('metrics.type', 'all');
          span?.setAttribute('refresh.auto', true);

          const results = await Promise.allSettled([
            this.analyticsService.getRTPMetrics(1),
            this.analyticsService.getSessionMetrics(),
            this.analyticsService.getFinancialMetrics(24),
          ]);

          let successCount = 0;
          let errorCount = 0;

          // RTP Metrics
          if (results[0].status === 'fulfilled') {
            this.rtpData = results[0].value;
            this.hasError = false;
            successCount++;
            span?.setAttribute('metrics.rtp.success', true);
            span?.setAttribute('rtp.value', this.rtpData.overallRtp);
            span?.setAttribute('rtp.status', this.rtpData.rtpThreshold.status);
          } else {
            errorCount++;
            span?.setAttribute('metrics.rtp.success', false);
            this.handleError('Failed to load RTP metrics', results[0].reason);
          }

          // Session Metrics
          if (results[1].status === 'fulfilled') {
            this.sessionData = results[1].value;
            successCount++;
            span?.setAttribute('metrics.sessions.success', true);
            span?.setAttribute('sessions.active', this.sessionData.activeSessions);
          } else {
            errorCount++;
            span?.setAttribute('metrics.sessions.success', false);
            this.handleError('Failed to load session metrics', results[1].reason);
          }

          // Financial Metrics
          if (results[2].status === 'fulfilled') {
            this.financialData = results[2].value;
            successCount++;
            span?.setAttribute('metrics.financial.success', true);
            span?.setAttribute('financial.revenue', this.financialData.totalRevenue);
          } else {
            errorCount++;
            span?.setAttribute('metrics.financial.success', false);
            this.handleError('Failed to load financial metrics', results[2].reason);
          }

          span?.setAttribute('metrics.success_count', successCount);
          span?.setAttribute('metrics.error_count', errorCount);

          setTransactionStatus(span, errorCount === 0);
        } catch (error: any) {
          setTransactionStatus(span, false, error);
          Sentry.captureException(error);
        }
      }
    );
  }

  private handleError(message: string, error: any): void {
    this.hasError = true;
    this.errorMessage = message;
    console.error(message, error);
    Sentry.captureException(error, {
      tags: {
        component: 'business-metrics',
        operation: 'load-metrics'
      }
    });
  }
}
