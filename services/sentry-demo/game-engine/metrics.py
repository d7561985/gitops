"""
Shared business metrics definitions and helpers for Sentry POC
"""
import time
from typing import Dict, Any, Optional
import sentry_sdk

class BusinessMetrics:
    """Business metric constants and helpers"""
    
    # Metric names
    RTP = "business.rtp"
    RTP_ROLLING = "business.rtp.rolling_24h"
    BET_VOLUME = "business.bet_volume"
    PAYOUT_VOLUME = "business.payout_volume"
    ACTIVE_SESSIONS = "business.active_sessions"
    WIN_RATE = "business.win_rate"
    AVERAGE_BET = "business.average_bet"
    SESSION_DURATION = "business.session_duration"
    
    # Financial metrics
    REVENUE_NET = "business.revenue.net"
    DEPOSIT_AMOUNT = "business.deposit.amount"
    WITHDRAWAL_AMOUNT = "business.withdrawal.amount"
    DEPOSIT_COUNT = "business.deposit.count"
    WITHDRAWAL_COUNT = "business.withdrawal.count"
    PAYMENT_SUCCESS_RATE = "business.payment.success_rate"
    
    # Player behavior
    PLAYER_LIFETIME_VALUE = "business.player.ltv"
    PLAYER_SESSION_COUNT = "business.player.sessions"
    PLAYER_CHURN_RISK = "business.player.churn_risk"
    
    @staticmethod
    def track_metric(name: str, value: float, unit: str = "none", tags: Optional[Dict[str, str]] = None):
        """Track a business metric in Sentry"""
        sentry_sdk.set_measurement(name, value, unit)
        if tags:
            for tag_name, tag_value in tags.items():
                sentry_sdk.set_tag(f"metric.{tag_name}", tag_value)
    
    @staticmethod
    def track_rtp(total_bets: float, total_payouts: float, period: str = "current"):
        """Calculate and track RTP (Return to Player) percentage"""
        if total_bets > 0:
            rtp = (total_payouts / total_bets) * 100
            BusinessMetrics.track_metric(
                BusinessMetrics.RTP, 
                rtp, 
                "percent",
                {"period": period}
            )
            return rtp
        return 0.0
    
    @staticmethod
    def track_session_metric(user_id: str, metric_name: str, value: float):
        """Track a session-specific metric"""
        sentry_sdk.set_tag("session.user_id", user_id)
        BusinessMetrics.track_metric(metric_name, value)
    
    @staticmethod
    def start_business_transaction(name: str, op: str = "business") -> Any:
        """Start a business-focused transaction"""
        transaction = sentry_sdk.start_transaction(
            name=name,
            op=op,
            custom_sampling_context={
                "business_critical": True
            }
        )
        transaction.set_tag("transaction.business", "true")
        return transaction


class MetricAnomalyDetector:
    """Simple anomaly detection for business metrics"""
    
    def __init__(self):
        self.thresholds = {
            BusinessMetrics.RTP: {"min": 85, "max": 98},  # RTP should be 85-98%
            BusinessMetrics.WIN_RATE: {"min": 20, "max": 50},  # Win rate 20-50%
            BusinessMetrics.PAYMENT_SUCCESS_RATE: {"min": 95, "max": 100},  # Payment success >95%
        }
    
    def check_anomaly(self, metric_name: str, value: float) -> Optional[str]:
        """Check if a metric value is anomalous"""
        if metric_name in self.thresholds:
            threshold = self.thresholds[metric_name]
            if value < threshold["min"]:
                return f"{metric_name} too low: {value:.2f} (expected >= {threshold['min']})"
            elif value > threshold["max"]:
                return f"{metric_name} too high: {value:.2f} (expected <= {threshold['max']})"
        return None
    
    def track_with_anomaly_detection(self, metric_name: str, value: float, **kwargs):
        """Track metric and detect anomalies"""
        BusinessMetrics.track_metric(metric_name, value, **kwargs)
        
        anomaly = self.check_anomaly(metric_name, value)
        if anomaly:
            sentry_sdk.capture_message(
                f"Business Metric Anomaly: {anomaly}",
                level="warning",
                tags={
                    "anomaly.type": "business_metric",
                    "anomaly.metric": metric_name,
                    "anomaly.value": value
                }
            )