"""
Game Engine - Clean Architecture Entry Point

Supports both HTTP REST and Connect protocols via environment variables:
- ENABLE_REST=true (default) - Enable HTTP REST endpoints
- ENABLE_CONNECT=true (default) - Enable Connect protocol endpoints
"""
import os
import sys
import logging

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sentry_sdk
from tornado import web, ioloop
from sentry_sdk.integrations.tornado import TornadoIntegration

from src.config.container import Container
from src.presentation.http.handlers import (
    CalculateHandler,
    BusinessMetricsHandler,
    HealthHandler,
    MetricsHandler
)
from src.presentation.connect.handlers import (
    ConnectCalculateHandler,
    ConnectBusinessMetricsHandler
)

# Import debug handlers from original (kept for Sentry demo purposes)
from debug_handlers import (
    DebugCrashHandler,
    DebugErrorHandler,
    DebugMemoryLeakHandler,
    DebugInfiniteLoopHandler,
    DebugAsyncErrorHandler,
    DebugThreadingErrorHandler
)

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# Configuration
version = os.environ.get('APP_VERSION', '1.0.0')
sentry_debug = os.environ.get('SENTRY_DEBUG', 'false').lower() == 'true'
sentry_profiles_rate = float(os.environ.get('SENTRY_PROFILES_SAMPLE_RATE', '0'))
sentry_traces_rate = float(os.environ.get('SENTRY_TRACES_SAMPLE_RATE', '1.0'))
sentry_environment = os.environ.get('SENTRY_ENVIRONMENT', 'development')

# Protocol flags
ENABLE_REST = os.environ.get('ENABLE_REST', 'true').lower() == 'true'
ENABLE_CONNECT = os.environ.get('ENABLE_CONNECT', 'true').lower() == 'true'

# Initialize Sentry
sentry_sdk.init(
    dsn=os.environ.get('SENTRY_DSN'),
    integrations=[TornadoIntegration()],
    traces_sample_rate=sentry_traces_rate,
    environment=sentry_environment,
    profiles_sample_rate=sentry_profiles_rate,
    debug=sentry_debug,
    release=f"game-engine@{version}",
    auto_session_tracking=True
)


def make_app():
    """Create Tornado application with Clean Architecture handlers"""
    # Get DI container
    container = Container.get_instance()

    # Base routes (always enabled)
    routes = [
        (r"/health", HealthHandler),
        (r"/metrics", MetricsHandler),
        # Debug endpoints for Sentry demo
        (r"/debug/crash", DebugCrashHandler),
        (r"/debug/error/(.*)", DebugErrorHandler),
        (r"/debug/memory-leak", DebugMemoryLeakHandler),
        (r"/debug/infinite-loop", DebugInfiniteLoopHandler),
        (r"/debug/async-error", DebugAsyncErrorHandler),
        (r"/debug/threading-error", DebugThreadingErrorHandler),
    ]

    # HTTP REST endpoints
    if ENABLE_REST:
        logger.info("Enabling HTTP REST endpoints")
        routes.extend([
            (r"/calculate", CalculateHandler, {
                "calculate_use_case": container.get_calculate_use_case()
            }),
            (r"/business-metrics", BusinessMetricsHandler, {
                "metrics_use_case": container.get_metrics_use_case()
            }),
        ])

    # Connect protocol endpoints
    if ENABLE_CONNECT:
        logger.info("Enabling Connect protocol endpoints")
        routes.extend([
            (r"/game.v1.GameEngineService/Calculate", ConnectCalculateHandler, {
                "calculate_use_case": container.get_calculate_use_case()
            }),
            (r"/game.v1.GameEngineService/TrackBusinessMetrics", ConnectBusinessMetricsHandler, {
                "metrics_use_case": container.get_metrics_use_case()
            }),
        ])

    return web.Application(routes)


if __name__ == "__main__":
    app = make_app()
    port = int(os.environ.get('PORT', 8082))
    app.listen(port)

    protocols = []
    if ENABLE_REST:
        protocols.append("REST")
    if ENABLE_CONNECT:
        protocols.append("Connect")

    print(f"Game Engine started on :{port}")
    print(f"Protocols enabled: {', '.join(protocols)}")
    print(f"Routes:")
    if ENABLE_REST:
        print(f"  REST:    POST /calculate, POST /business-metrics")
    if ENABLE_CONNECT:
        print(f"  Connect: POST /game.v1.GameEngineService/Calculate")
        print(f"           POST /game.v1.GameEngineService/TrackBusinessMetrics")

    ioloop.IOLoop.current().start()
