const Sentry = require('@sentry/node');
const { createTrackMetricsResponse } = require('../dto');

/**
 * Track Financial Metrics Use Case
 * Handles financial metrics tracking and anomaly simulation
 */
class TrackFinancialMetricsUseCase {
  /**
   * @param {MetricsServicePort} metricsService
   * @param {Object} db - Database connection for stats
   */
  constructor(metricsService, db) {
    this.metricsService = metricsService;
    this.db = db;
  }

  /**
   * Execute metrics tracking
   * @param {TrackFinancialMetricsRequest} request
   * @returns {Promise<TrackFinancialMetricsResponse>}
   */
  async execute(request) {
    const { scenario } = request;

    switch (scenario) {
      case 'payment_failure_spike':
        return await this.simulatePaymentFailures();

      case 'revenue_anomaly':
        return await this.simulateRevenueAnomaly();

      default:
        return await this.trackNormalMetrics();
    }
  }

  async simulatePaymentFailures() {
    await Sentry.startSpan(
      { name: 'Simulate payment failures', op: 'demo.payment_failures' },
      async () => {
        // Track declining success rate
        this.metricsService.trackMetric('payment_success_rate', 85.0, 'percent', {
          scenario: 'demo',
          alert: 'critical'
        });

        // Capture multiple errors
        for (let i = 0; i < 5; i++) {
          Sentry.captureException(new Error(`Payment provider error ${i + 1}`));
        }
      }
    );

    return createTrackMetricsResponse({
      status: 'Payment failure spike triggered',
      metrics: { successRate: 85.0 }
    });
  }

  async simulateRevenueAnomaly() {
    await Sentry.startSpan(
      { name: 'Simulate revenue anomaly', op: 'demo.revenue_anomaly' },
      async () => {
        this.metricsService.trackMetric('revenue_net', -5000, 'currency');
        this.metricsService.trackMetric('deposit_amount', 1000, 'currency');
        this.metricsService.trackMetric('withdrawal_amount', 6000, 'currency');

        Sentry.captureMessage('Revenue Alert: Negative daily revenue detected', 'error');
      }
    );

    return createTrackMetricsResponse({
      status: 'Revenue anomaly triggered',
      metrics: { netRevenue: -5000 }
    });
  }

  async trackNormalMetrics() {
    await Sentry.startSpan(
      { name: 'Normal financial metrics', op: 'demo.normal' },
      async () => {
        this.metricsService.trackMetric('payment_success_rate', 98.5, 'percent');
        this.metricsService.trackMetric('revenue_net', 2500, 'currency');
        this.metricsService.trackMetric('deposit_amount', 10000, 'currency');
        this.metricsService.trackMetric('withdrawal_amount', 7500, 'currency');
      }
    );

    return createTrackMetricsResponse({
      status: 'Normal financial metrics tracked',
      metrics: { successRate: 98.5, netRevenue: 2500 }
    });
  }
}

module.exports = { TrackFinancialMetricsUseCase };
