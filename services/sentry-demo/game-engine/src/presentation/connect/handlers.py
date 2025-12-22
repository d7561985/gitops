"""Connect protocol handlers for game engine

Uses generated protobuf classes for type-safe JSON serialization.
Connect Protocol = HTTP POST + JSON with specific URL patterns
Routes: /game.v1.GameEngineService/Calculate
        /game.v1.GameEngineService/TrackBusinessMetrics
"""
import json
import sentry_sdk
from tornado import web
from google.protobuf.json_format import Parse, MessageToJson

from src.application.dto.calculate_request import CalculateRequest
from src.application.dto.business_metrics_request import BusinessMetricsRequest
from src.application.use_cases.calculate_game_result_use_case import CalculateGameResultUseCase
from src.application.use_cases.track_business_metrics_use_case import TrackBusinessMetricsUseCase

# Generated protobuf classes from @gitops-poc-dzha/game-engine-python
from game.v1 import game_pb2


class ConnectCalculateHandler(web.RequestHandler):
    """Connect protocol handler for game calculation

    Route: POST /game.v1.GameEngineService/Calculate
    """

    def initialize(self, calculate_use_case: CalculateGameResultUseCase):
        self.calculate_use_case = calculate_use_case

    async def post(self):
        """Connect: Calculate game result"""
        # Continue trace from upstream
        sentry_trace = self.request.headers.get("sentry-trace")
        baggage = self.request.headers.get("baggage")

        transaction = sentry_sdk.continue_trace({
            "sentry-trace": sentry_trace,
            "baggage": baggage
        }, op="game.calculate", name="connect_calculate_game_result")

        with sentry_sdk.start_transaction(transaction):
            try:
                # Parse request using generated protobuf class
                proto_request = game_pb2.CalculateRequest()
                if self.request.body:
                    Parse(self.request.body, proto_request)

                # Create application DTO from proto
                request = CalculateRequest(
                    user_id=proto_request.user_id,
                    bet=proto_request.bet,
                    cpu_intensive=proto_request.cpu_intensive
                )

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
                    self._connect_error(result.error, "internal")
                else:
                    # Build response using generated protobuf class
                    proto_response = game_pb2.CalculateResponse()
                    proto_response.win = result.win
                    proto_response.payout = result.payout
                    proto_response.symbols.extend(result.symbols)
                    proto_response.new_balance = result.new_balance

                    if result.wagering_progress:
                        proto_response.wagering_progress.progress_percent = result.wagering_progress.get('progress_percent', 0)
                        proto_response.wagering_progress.remaining = result.wagering_progress.get('remaining', 0)
                        proto_response.wagering_progress.can_convert = result.wagering_progress.get('can_convert', False)

                    self.set_status(200)
                    self.set_header('Content-Type', 'application/json')
                    # Use MessageToJson for proper camelCase conversion
                    self.write(MessageToJson(proto_response, preserving_proto_field_name=False))

            except json.JSONDecodeError as e:
                self._connect_error(str(e), "invalid_argument")
            except Exception as e:
                sentry_sdk.capture_exception(e)
                self._connect_error(str(e), "internal")

    def _connect_error(self, message: str, code: str):
        """Return Connect protocol error response"""
        status_map = {
            "invalid_argument": 400,
            "not_found": 404,
            "failed_precondition": 412,
            "internal": 500
        }
        self.set_status(status_map.get(code, 500))
        self.set_header('Content-Type', 'application/json')
        self.write({
            "code": code,
            "message": message
        })


class ConnectBusinessMetricsHandler(web.RequestHandler):
    """Connect protocol handler for business metrics

    Route: POST /game.v1.GameEngineService/TrackBusinessMetrics
    """

    def initialize(self, metrics_use_case: TrackBusinessMetricsUseCase):
        self.metrics_use_case = metrics_use_case

    async def post(self):
        """Connect: Track business metrics"""
        sentry_trace = self.request.headers.get('sentry-trace', '')
        baggage = self.request.headers.get('baggage', '')

        if sentry_trace:
            transaction = sentry_sdk.continue_trace({
                "sentry-trace": sentry_trace,
                "baggage": baggage
            }, op="business.demo", name="connect_business_metrics")
        else:
            transaction = {"op": "business.demo", "name": "connect_business_metrics"}

        with sentry_sdk.start_transaction(transaction):
            try:
                # Parse request using generated protobuf class
                proto_request = game_pb2.TrackBusinessMetricsRequest()
                if self.request.body:
                    Parse(self.request.body, proto_request)

                # Create application DTO from proto
                request = BusinessMetricsRequest(scenario=proto_request.scenario)

                # Execute use case
                result = self.metrics_use_case.execute(request)

                if result.error:
                    self._connect_error(result.error, "internal")
                else:
                    # Build response using generated protobuf class
                    proto_response = game_pb2.TrackBusinessMetricsResponse()
                    proto_response.status = result.status
                    if result.metrics:
                        for key, value in result.metrics.items():
                            proto_response.metrics[key] = value

                    self.set_status(200)
                    self.set_header('Content-Type', 'application/json')
                    self.write(MessageToJson(proto_response, preserving_proto_field_name=False))

            except json.JSONDecodeError as e:
                self._connect_error(str(e), "invalid_argument")
            except Exception as e:
                sentry_sdk.capture_exception(e)
                self._connect_error(str(e), "internal")

    def _connect_error(self, message: str, code: str):
        """Return Connect protocol error response"""
        status_map = {
            "invalid_argument": 400,
            "not_found": 404,
            "internal": 500
        }
        self.set_status(status_map.get(code, 500))
        self.set_header('Content-Type', 'application/json')
        self.write({
            "code": code,
            "message": message
        })
