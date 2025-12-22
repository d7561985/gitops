"""Track business metrics use case"""
import logging
import sentry_sdk
from sentry_sdk import start_span

from src.application.dto.business_metrics_request import BusinessMetricsRequest
from src.application.dto.business_metrics_response import BusinessMetricsResponse
from metrics import BusinessMetrics, MetricAnomalyDetector

logger = logging.getLogger(__name__)


class TrackBusinessMetricsUseCase:
    """Use case for tracking business metrics (demo scenarios)"""

    def execute(self, request: BusinessMetricsRequest) -> BusinessMetricsResponse:
        """Execute business metrics tracking based on scenario"""
        try:
            scenario = request.scenario

            if scenario == 'rtp_anomaly':
                return self._handle_rtp_anomaly()
            elif scenario == 'session_surge':
                return self._handle_session_surge()
            elif scenario == 'win_rate_manipulation':
                return self._handle_win_rate_anomaly()
            else:
                return self._handle_normal_metrics()

        except Exception as e:
            sentry_sdk.capture_exception(e)
            return BusinessMetricsResponse(
                status="error",
                error=str(e)
            )

    def _handle_rtp_anomaly(self) -> BusinessMetricsResponse:
        """Simulate RTP dropping below threshold"""
        with start_span(op="demo.rtp_anomaly", description="Simulate RTP anomaly"):
            anomaly_detector = MetricAnomalyDetector()

            # Track abnormally low RTP
            anomaly_detector.track_with_anomaly_detection(
                BusinessMetrics.RTP,
                75.0,  # Below 85% threshold
                unit="percent",
                tags={"scenario": "demo", "alert": "critical"}
            )

            # Track abnormally high RTP
            anomaly_detector.track_with_anomaly_detection(
                BusinessMetrics.RTP,
                99.5,  # Above 98% threshold
                unit="percent",
                tags={"scenario": "demo", "alert": "warning"}
            )

        return BusinessMetricsResponse(
            status="RTP anomaly triggered",
            data={"lowRtp": 75.0, "highRtp": 99.5}
        )

    def _handle_session_surge(self) -> BusinessMetricsResponse:
        """Simulate sudden increase in active sessions"""
        with start_span(op="demo.session_surge", description="Simulate session surge"):
            # Normal sessions
            BusinessMetrics.track_metric(BusinessMetrics.ACTIVE_SESSIONS, 150, "none")
            # Sudden surge
            BusinessMetrics.track_metric(
                BusinessMetrics.ACTIVE_SESSIONS,
                850,
                "none",
                {"surge": "true", "alert": "info"}
            )

        return BusinessMetricsResponse(
            status="Session surge triggered",
            data={"normal": 150, "surge": 850}
        )

    def _handle_win_rate_anomaly(self) -> BusinessMetricsResponse:
        """Simulate suspicious win rate patterns"""
        with start_span(op="demo.win_rate", description="Simulate win rate manipulation"):
            anomaly_detector = MetricAnomalyDetector()

            # Abnormally high win rate
            anomaly_detector.track_with_anomaly_detection(
                BusinessMetrics.WIN_RATE,
                85.0,  # Way above 50% threshold
                unit="percent",
                tags={"scenario": "demo", "alert": "critical", "fraud_risk": "high"}
            )

        return BusinessMetricsResponse(
            status="Win rate anomaly triggered",
            data={"suspiciousRate": 85.0}
        )

    def _handle_normal_metrics(self) -> BusinessMetricsResponse:
        """Track normal metrics"""
        with start_span(op="demo.normal", description="Normal business metrics"):
            BusinessMetrics.track_metric(BusinessMetrics.RTP, 95.5, "percent")
            BusinessMetrics.track_metric(BusinessMetrics.WIN_RATE, 35.0, "percent")
            BusinessMetrics.track_metric(BusinessMetrics.ACTIVE_SESSIONS, 250, "none")

        return BusinessMetricsResponse(status="Normal metrics tracked")
