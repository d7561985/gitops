/**
 * Shared business metrics definitions and helpers for Sentry POC
 */
const Sentry = require('@sentry/node');

class BusinessMetrics {
    // Metric names
    static RTP = "business.rtp";
    static RTP_ROLLING = "business.rtp.rolling_24h";
    static BET_VOLUME = "business.bet_volume";
    static PAYOUT_VOLUME = "business.payout_volume";
    static ACTIVE_SESSIONS = "business.active_sessions";
    static WIN_RATE = "business.win_rate";
    static AVERAGE_BET = "business.average_bet";
    static SESSION_DURATION = "business.session_duration";
    
    // Financial metrics
    static REVENUE_NET = "business.revenue.net";
    static DEPOSIT_AMOUNT = "business.deposit.amount";
    static WITHDRAWAL_AMOUNT = "business.withdrawal.amount";
    static DEPOSIT_COUNT = "business.deposit.count";
    static WITHDRAWAL_COUNT = "business.withdrawal.count";
    static PAYMENT_SUCCESS_RATE = "business.payment.success_rate";
    
    // Player behavior
    static PLAYER_LIFETIME_VALUE = "business.player.ltv";
    static PLAYER_SESSION_COUNT = "business.player.sessions";
    static PLAYER_CHURN_RISK = "business.player.churn_risk";
    
    /**
     * Track a business metric in Sentry
     */
    static trackMetric(name, value, unit = "none", tags = {}) {
        // Set measurements within a span context if available
        try {
            const activeSpan = Sentry.getActiveSpan();
            if (activeSpan && typeof activeSpan.setMeasurement === 'function') {
                activeSpan.setMeasurement(name, value, unit);
            }
            // Always set tags
            Object.entries(tags).forEach(([key, val]) => {
                Sentry.setTag(`metric.${key}`, val);
            });
        } catch (e) {
            // Ignore errors in metrics tracking
            console.log('Metrics tracking error:', e.message);
        }
    }
    
    /**
     * Calculate and track RTP (Return to Player) percentage
     */
    static trackRtp(totalBets, totalPayouts, period = "current") {
        if (totalBets > 0) {
            const rtp = (totalPayouts / totalBets) * 100;
            this.trackMetric(
                this.RTP, 
                rtp, 
                "percent",
                { period }
            );
            return rtp;
        }
        return 0.0;
    }
    
    /**
     * Track a session-specific metric
     */
    static trackSessionMetric(userId, metricName, value) {
        Sentry.setTag("session.user_id", userId);
        this.trackMetric(metricName, value);
    }
    
    /**
     * Start a business-focused transaction OR continue existing trace
     */
    static startBusinessTransaction(name, op = "business") {
        // Check if there's already an active transaction from incoming trace
        const activeSpan = Sentry.getActiveSpan();
        
        if (activeSpan) {
            // We have an incoming trace - just add our business tags
            const transaction = Sentry.getRootSpan(activeSpan);
            if (transaction) {
                transaction.setTag("transaction.business", "true");
                // Update transaction name for better visibility
                transaction.updateName(name);
                return transaction;
            }
        }
        
        // No incoming trace - create new transaction
        const transaction = Sentry.startTransaction({
            name,
            op,
            data: {
                business_critical: true
            }
        });
        transaction.setTag("transaction.business", "true");
        return transaction;
    }
}

class MetricAnomalyDetector {
    constructor() {
        this.thresholds = {
            [BusinessMetrics.RTP]: { min: 85, max: 98 }, // RTP should be 85-98%
            [BusinessMetrics.WIN_RATE]: { min: 20, max: 50 }, // Win rate 20-50%
            [BusinessMetrics.PAYMENT_SUCCESS_RATE]: { min: 95, max: 100 }, // Payment success >95%
        };
    }
    
    /**
     * Check if a metric value is anomalous
     */
    checkAnomaly(metricName, value) {
        const threshold = this.thresholds[metricName];
        if (threshold) {
            if (value < threshold.min) {
                return `${metricName} too low: ${value.toFixed(2)} (expected >= ${threshold.min})`;
            } else if (value > threshold.max) {
                return `${metricName} too high: ${value.toFixed(2)} (expected <= ${threshold.max})`;
            }
        }
        return null;
    }
    
    /**
     * Track metric and detect anomalies
     */
    trackWithAnomalyDetection(metricName, value, ...args) {
        BusinessMetrics.trackMetric(metricName, value, ...args);
        
        const anomaly = this.checkAnomaly(metricName, value);
        if (anomaly) {
            Sentry.captureMessage(
                `Business Metric Anomaly: ${anomaly}`,
                'warning'
            );
            Sentry.setTag("anomaly.type", "business_metric");
            Sentry.setTag("anomaly.metric", metricName);
            Sentry.setTag("anomaly.value", value);
        }
    }
}

module.exports = {
    BusinessMetrics,
    MetricAnomalyDetector
};