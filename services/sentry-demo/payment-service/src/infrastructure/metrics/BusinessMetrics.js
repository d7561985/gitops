const Sentry = require('@sentry/node');

/**
 * Business Metrics Service
 * Implements MetricsServicePort
 */
class BusinessMetrics {
  static PAYMENT_SUCCESS_RATE = 'payment_success_rate';
  static REVENUE_NET = 'revenue_net';
  static DEPOSIT_AMOUNT = 'deposit_amount';
  static WITHDRAWAL_AMOUNT = 'withdrawal_amount';
  static DEPOSIT_COUNT = 'deposit_count';
  static WITHDRAWAL_COUNT = 'withdrawal_count';

  /**
   * Track a metric
   * @param {string} name
   * @param {number} value
   * @param {string} unit
   * @param {Object} tags
   */
  trackMetric(name, value, unit = 'none', tags = {}) {
    // Sentry metrics
    Sentry.metrics.distribution(`business.${name}`, value, {
      unit,
      tags
    });

    // Could add Prometheus metrics here too
  }

  /**
   * Track with anomaly detection
   * @param {string} name
   * @param {number} value
   * @param {string} unit
   * @param {Object} tags
   */
  trackWithAnomalyDetection(name, value, unit, tags = {}) {
    this.trackMetric(name, value, unit, tags);

    // Simple threshold-based anomaly detection
    const thresholds = {
      [BusinessMetrics.PAYMENT_SUCCESS_RATE]: { min: 95, max: 100 },
      [BusinessMetrics.REVENUE_NET]: { min: 0, max: Infinity }
    };

    const threshold = thresholds[name];
    if (threshold) {
      if (value < threshold.min) {
        Sentry.captureMessage(
          `Anomaly detected: ${name} is ${value} (below ${threshold.min})`,
          'warning'
        );
      }
      if (value > threshold.max) {
        Sentry.captureMessage(
          `Anomaly detected: ${name} is ${value} (above ${threshold.max})`,
          'warning'
        );
      }
    }
  }
}

module.exports = { BusinessMetrics };
