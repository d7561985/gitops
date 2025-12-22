"""HTTP REST handlers for game engine"""
import json
import sentry_sdk
from tornado import web
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from src.application.dto.calculate_request import CalculateRequest
from src.application.dto.business_metrics_request import BusinessMetricsRequest
from src.application.use_cases.calculate_game_result_use_case import CalculateGameResultUseCase
from src.application.use_cases.track_business_metrics_use_case import TrackBusinessMetricsUseCase


class HealthHandler(web.RequestHandler):
    """Health check endpoint"""

    def get(self):
        self.write({"status": "ok"})


class MetricsHandler(web.RequestHandler):
    """Prometheus metrics endpoint"""

    def get(self):
        self.set_header('Content-Type', CONTENT_TYPE_LATEST)
        self.write(generate_latest())


class CalculateHandler(web.RequestHandler):
    """HTTP REST handler for game calculation"""

    def initialize(self, calculate_use_case: CalculateGameResultUseCase):
        self.calculate_use_case = calculate_use_case

    async def post(self):
        """POST /calculate - Calculate game result (REST API)"""
        # Continue trace from upstream
        sentry_trace = self.request.headers.get("sentry-trace")
        baggage = self.request.headers.get("baggage")

        transaction = sentry_sdk.continue_trace({
            "sentry-trace": sentry_trace,
            "baggage": baggage
        }, op="game.calculate", name="calculate_game_result")

        with sentry_sdk.start_transaction(transaction):
            try:
                data = json.loads(self.request.body)

                # Create request from snake_case (REST convention)
                request = CalculateRequest.from_snake_case(data)

                # Set user context
                sentry_sdk.set_user({"id": request.user_id})

                # Get trace headers for propagation
                current_span = sentry_sdk.get_current_span()
                trace_headers = {
                    'sentry-trace': current_span.to_traceparent() if current_span else '',
                    'baggage': sentry_sdk.get_baggage() or ''
                }

                # Execute use case
                result = self.calculate_use_case.execute(request, trace_headers)

                if result.error:
                    self.set_status(500)
                    self.write({"error": result.error})
                else:
                    # Return snake_case for REST API
                    self.set_status(200)
                    self.write(result.to_snake_case())

            except Exception as e:
                sentry_sdk.capture_exception(e)
                self.set_status(500)
                self.write({"error": str(e)})


class BusinessMetricsHandler(web.RequestHandler):
    """HTTP REST handler for business metrics"""

    def initialize(self, metrics_use_case: TrackBusinessMetricsUseCase):
        self.metrics_use_case = metrics_use_case

    async def post(self):
        """POST /business-metrics - Track business metrics"""
        sentry_trace = self.request.headers.get('sentry-trace', '')
        baggage = self.request.headers.get('baggage', '')

        if sentry_trace:
            transaction = sentry_sdk.continue_trace({
                "sentry-trace": sentry_trace,
                "baggage": baggage
            }, op="business.demo", name="business_metrics_scenario")
        else:
            transaction = {"op": "business.demo", "name": "business_metrics_scenario"}

        with sentry_sdk.start_transaction(transaction):
            try:
                data = json.loads(self.request.body)
                request = BusinessMetricsRequest.from_dict(data)
                result = self.metrics_use_case.execute(request)

                if result.error:
                    self.set_status(500)
                    self.write({"error": result.error})
                else:
                    self.set_status(200)
                    self.write(result.to_dict())

            except Exception as e:
                sentry_sdk.capture_exception(e)
                self.set_status(500)
                self.write({"error": str(e)})
