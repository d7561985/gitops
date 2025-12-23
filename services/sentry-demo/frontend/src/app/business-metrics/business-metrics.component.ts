import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { interval, Subscription } from 'rxjs';
import * as Sentry from '@sentry/angular';
import { 
  createNewTrace, 
  TransactionNames, 
  Operations, 
  setTransactionStatus 
} from '../utils/sentry-traces';

interface MetricData {
  period_hours: number;
  overall_rtp: number;
  rtp_threshold: {
    min: number;
    max: number;
    status: string;
  };
  game_count?: number;
  unique_players?: number;
  total_revenue?: number;
  total_payouts?: number;
  avg_deposit?: number;
  avg_withdrawal?: number;
  deposit_count?: number;
  withdrawal_count?: number;
  sessions?: any[];
}

@Component({
    selector: 'app-business-metrics',
    standalone: true,
    imports: [CommonModule],
    template: `
    <div class="metrics-dashboard">
      <h2>📊 Business Metrics Dashboard</h2>
    
      <div class="metrics-grid">
        <!-- RTP Metric Card -->
        <div class="metric-card" [class.anomaly]="rtpData?.rtp_threshold?.status === 'anomaly'">
          <h3>Return to Player (RTP)</h3>
          <div class="metric-value">{{ rtpData?.overall_rtp?.toFixed(2) || '0.00' }}%</div>
          <div class="metric-status" [class.warning]="rtpData?.rtp_threshold?.status === 'anomaly'">
            {{ rtpData?.rtp_threshold?.status === 'anomaly' ? '⚠️ Anomaly Detected' : '✅ Normal' }}
          </div>
          <div class="metric-range">Expected: {{ rtpData?.rtp_threshold?.min }}-{{ rtpData?.rtp_threshold?.max }}%</div>
        </div>
    
        <!-- Session Metrics Card -->
        <div class="metric-card">
          <h3>Active Sessions</h3>
          <div class="metric-value">{{ sessionData?.active_sessions || 0 }}</div>
          <div class="metric-subtext">Avg Duration: {{ sessionData?.avg_duration?.toFixed(0) || 0 }}s</div>
        </div>
    
        <!-- Financial Metrics Card -->
        <div class="metric-card">
          <h3>Financial Overview (24h)</h3>
          <div class="metric-row">
            <span>Revenue:</span>
            <span class="value">{{ '$' + (financialData?.total_revenue?.toFixed(2) || '0.00') }}</span>
          </div>
          <div class="metric-row">
            <span>Deposits:</span>
            <span class="value">{{ financialData?.deposit_count || 0 }} ({{ '$' + (financialData?.avg_deposit?.toFixed(2) || '0.00') }} avg)</span>
          </div>
          <div class="metric-row">
            <span>Withdrawals:</span>
            <span class="value">{{ financialData?.withdrawal_count || 0 }} ({{ '$' + (financialData?.avg_withdrawal?.toFixed(2) || '0.00') }} avg)</span>
          </div>
        </div>
    
        <!-- Game Activity Card -->
        <div class="metric-card">
          <h3>Game Activity</h3>
          <div class="metric-value">{{ rtpData?.game_count || 0 }}</div>
          <div class="metric-subtext">Games in last hour</div>
          <div class="metric-subtext">{{ rtpData?.unique_players || 0 }} unique players</div>
        </div>
      </div>
    
      <div class="refresh-info">
        Auto-refreshing every 10 seconds
        <span class="status" [class.error]="hasError">{{ hasError ? '❌ Error' : '🟢 Connected' }}</span>
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
  rtpData: MetricData | null = null;
  sessionData: any = null;
  financialData: MetricData | null = null;
  hasError = false;
  errorMessage = '';
  
  private refreshSubscription?: Subscription;
  // Use api-gateway for analytics service (relative URL for production)
  private analyticsUrl = '/api/analytics';

  constructor(private http: HttpClient) {}

  ngOnInit(): void {
    // Initial load
    this.loadMetrics();
    
    // Set up auto-refresh every 10 seconds
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
          
          // Track the number of successful API calls
          let successCount = 0;
          let errorCount = 0;
          
          // Load RTP metrics
          this.http.get<MetricData>(`${this.analyticsUrl}/api/v1/business-metrics/rtp?hours=1`)
            .subscribe({
              next: (data) => {
                this.rtpData = data;
                this.hasError = false;
                successCount++;
                span?.setAttribute('metrics.rtp.success', true);
                span?.setAttribute('rtp.value', data.overall_rtp);
                span?.setAttribute('rtp.status', data.rtp_threshold?.status || 'normal');
              },
              error: (err) => {
                errorCount++;
                span?.setAttribute('metrics.rtp.success', false);
                this.handleError('Failed to load RTP metrics', err);
              }
            });

          // Load session metrics
          this.http.get<any>(`${this.analyticsUrl}/api/v1/business-metrics/sessions`)
            .subscribe({
              next: (data) => {
                this.sessionData = data;
                successCount++;
                span?.setAttribute('metrics.sessions.success', true);
                span?.setAttribute('sessions.active', data.active_sessions || 0);
              },
              error: (err) => {
                errorCount++;
                span?.setAttribute('metrics.sessions.success', false);
                this.handleError('Failed to load session metrics', err);
              }
            });

          // Load financial metrics
          this.http.get<MetricData>(`${this.analyticsUrl}/api/v1/business-metrics/financial?hours=24`)
            .subscribe({
              next: (data) => {
                this.financialData = data;
                successCount++;
                span?.setAttribute('metrics.financial.success', true);
                span?.setAttribute('financial.revenue', data.total_revenue || 0);
              },
              error: (err) => {
                errorCount++;
                span?.setAttribute('metrics.financial.success', false);
                this.handleError('Failed to load financial metrics', err);
              }
            });
          
          // Add a small delay to ensure all requests have been initiated
          await new Promise(resolve => setTimeout(resolve, 100));
          
          // Set final transaction status based on overall success
          span?.setAttribute('metrics.success_count', successCount);
          span?.setAttribute('metrics.error_count', errorCount);
          
          // Transaction is successful even if some metrics fail
          setTransactionStatus(span, true);
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