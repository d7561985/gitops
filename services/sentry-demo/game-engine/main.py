"""
Game Engine - Entry Point Wrapper

This file maintains backward compatibility.
For Clean Architecture implementation, see src/main.py

Environment variables for protocol switching:
- ENABLE_REST=true (default) - Enable HTTP REST endpoints
- ENABLE_CONNECT=true (default) - Enable Connect protocol endpoints
- USE_CLEAN_ARCH=true - Use new Clean Architecture (default: false for compatibility)
"""
import os
import json
import time
import random
import logging
import numpy as np
import psutil
import asyncio
import threading
import traceback
import tornado
import requests
from tornado import web, ioloop
from pymongo import MongoClient, ReturnDocument
import sentry_sdk
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from sentry_sdk.integrations.tornado import TornadoIntegration
from sentry_sdk import start_transaction, start_span
from rabbitmq_publisher import get_publisher
from metrics import BusinessMetrics, MetricAnomalyDetector

# Check if we should use Clean Architecture
USE_CLEAN_ARCH = os.environ.get('USE_CLEAN_ARCH', 'false').lower() == 'true'

if USE_CLEAN_ARCH:
    # Use new Clean Architecture entry point
    from src.main import make_app

    if __name__ == "__main__":
        app = make_app()
        port = int(os.environ.get('PORT', 8082))
        app.listen(port)
        print(f"Game Engine (Clean Architecture) started on :{port}")
        ioloop.IOLoop.current().start()
else:
    # Original implementation below (for backward compatibility)
    pass

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# Get version from environment or use default
version = os.environ.get('APP_VERSION', '1.0.0')

# Sentry configuration from environment
sentry_debug = os.environ.get('SENTRY_DEBUG', 'false').lower() == 'true'
sentry_profiles_rate = float(os.environ.get('SENTRY_PROFILES_SAMPLE_RATE', '0'))
sentry_traces_rate = float(os.environ.get('SENTRY_TRACES_SAMPLE_RATE', '1.0'))
sentry_environment = os.environ.get('SENTRY_ENVIRONMENT', 'development')

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

# =============================================================================
# Prometheus Metrics
# =============================================================================
REQUEST_COUNT = Counter(
    'game_engine_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)
REQUEST_LATENCY = Histogram(
    'game_engine_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint'],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)
GAME_CALCULATIONS = Counter(
    'game_engine_calculations_total',
    'Total game calculations',
    ['result']  # win, lose
)
BET_AMOUNT = Histogram(
    'game_engine_bet_amount',
    'Bet amounts distribution',
    buckets=[1, 5, 10, 25, 50, 100, 250, 500, 1000]
)
PAYOUT_AMOUNT = Histogram(
    'game_engine_payout_amount',
    'Payout amounts distribution',
    buckets=[0, 1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500]
)
ACTIVE_USERS = Gauge(
    'game_engine_active_users',
    'Number of active users (approximate)'
)

class MetricsHandler(web.RequestHandler):
    """Prometheus metrics endpoint"""
    def get(self):
        self.set_header('Content-Type', CONTENT_TYPE_LATEST)
        self.write(generate_latest())

# MongoDB connection
mongo_url = os.environ.get('MONGODB_URL', 'mongodb://admin:password@localhost:27017')
mongo_client = MongoClient(mongo_url)
db = mongo_client.sentry_poc

# Balance management configuration
# Set USE_EXTERNAL_BALANCE=true to use external user-service for balance
USE_EXTERNAL_BALANCE = os.environ.get('USE_EXTERNAL_BALANCE', 'false').lower() == 'true'
USER_SERVICE_URL = os.environ.get('USER_SERVICE_URL', 'http://sentry-user-sv:8081')
DEFAULT_BALANCE = float(os.environ.get('DEFAULT_BALANCE', '1000'))

# Wager service integration
# Set USE_WAGER_SERVICE=true to integrate with wager-service for bonus tracking
USE_WAGER_SERVICE = os.environ.get('USE_WAGER_SERVICE', 'false').lower() == 'true'
WAGER_SERVICE_URL = os.environ.get('WAGER_SERVICE_URL', 'http://sentry-wager-sv:8085')

def get_user_balance(user_id: str) -> float:
    """Get user balance from MongoDB or external service"""
    if USE_EXTERNAL_BALANCE:
        # TODO: Call external user-service
        # response = requests.get(f"{USER_SERVICE_URL}/balance/{user_id}")
        # return response.json().get('balance', DEFAULT_BALANCE)
        return DEFAULT_BALANCE

    # Use local MongoDB balance tracking
    user = db.user_balances.find_one({"user_id": user_id})
    if user:
        return user.get('balance', DEFAULT_BALANCE)

    # Create new user with default balance
    db.user_balances.insert_one({
        "user_id": user_id,
        "balance": DEFAULT_BALANCE,
        "created_at": time.time()
    })
    return DEFAULT_BALANCE

def update_user_balance(user_id: str, bet: float, payout: float) -> float:
    """Update user balance and return new balance"""
    if USE_EXTERNAL_BALANCE:
        # TODO: Call external user-service
        return DEFAULT_BALANCE

    # Atomic update in MongoDB
    result = db.user_balances.find_one_and_update(
        {"user_id": user_id},
        {
            "$inc": {"balance": -bet + payout},
            "$set": {"updated_at": time.time()}
        },
        upsert=True,
        return_document=ReturnDocument.AFTER
    )

    # Handle case where user didn't exist (upsert created with only the $inc)
    if result.get('balance') is None or result.get('balance') < 0:
        # Reset to default minus bet plus payout
        new_balance = DEFAULT_BALANCE - bet + payout
        db.user_balances.update_one(
            {"user_id": user_id},
            {"$set": {"balance": new_balance}}
        )
        return new_balance

    return result.get('balance', DEFAULT_BALANCE)


def validate_wager_with_service(user_id: str, bet: float, game_id: str = "slot-machine") -> dict:
    """Validate wager with wager-service before processing spin"""
    if not USE_WAGER_SERVICE:
        return None

    try:
        response = requests.post(
            f"{WAGER_SERVICE_URL}/validate",
            json={
                "user_id": user_id,
                "amount": bet,
                "game_id": game_id
            },
            timeout=5
        )
        if response.status_code == 200:
            return response.json()
        else:
            logger.warning(f"Wager validation failed: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        logger.error(f"Failed to validate wager: {e}")
        return None


def place_wager_with_service(validation_data: dict, game_result: str, payout: float) -> dict:
    """Place wager with wager-service after spin completes"""
    if not USE_WAGER_SERVICE or not validation_data:
        return None

    try:
        response = requests.post(
            f"{WAGER_SERVICE_URL}/place",
            json={
                "validation_data": validation_data,
                "game_result": game_result,
                "payout": payout
            },
            timeout=5
        )
        if response.status_code == 200:
            result = response.json()
            logger.info(f"Wager placed successfully: {result.get('wager_id')}")
            return result
        else:
            logger.warning(f"Wager placement failed: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        logger.error(f"Failed to place wager: {e}")
        return None


class HealthHandler(web.RequestHandler):
    def get(self):
        self.write({"status": "ok"})

class CalculateHandler(web.RequestHandler):
    async def post(self):
        # Continue the trace from upstream
        sentry_trace = self.request.headers.get("sentry-trace")
        baggage = self.request.headers.get("baggage")
        
        transaction = sentry_sdk.continue_trace({
            "sentry-trace": sentry_trace,
            "baggage": baggage
        }, op="game.calculate", name="calculate_game_result")
        
        with sentry_sdk.start_transaction(transaction):
            try:
                data = json.loads(self.request.body)
                user_id = data.get('userId')
                bet = data.get('bet')
                cpu_intensive = data.get('cpu_intensive', False)
                
                # Start span for RNG calculation
                with start_span(op="game.rng", description="Calculate slot result") as span:
                    if cpu_intensive:
                        # INTENTIONAL CPU SPIKE for demo
                        # Simulate inefficient RNG calculation with prime numbers
                        result = self._calculate_slot_result_cpu_intensive()
                        span.set_data("calculation_method", "cpu_intensive_primes")
                        span.set_tag("performance.issue", "cpu_spike")
                    else:
                        # Normal efficient calculation
                        result = self._calculate_slot_result_normal()
                        span.set_data("calculation_method", "normal")
                
                # Calculate payout
                win = result['win']
                payout = bet * result['multiplier'] if win else 0
                
                # Store game result in MongoDB
                with start_span(op="db.insert", description="Store game result") as span:
                    span.set_data("db.system", "mongodb")
                    span.set_data("db.collection", "games")
                    
                    game_record = {
                        "user_id": user_id,
                        "bet": bet,
                        "win": win,
                        "payout": payout,
                        "symbols": result['symbols'],
                        "timestamp": time.time()
                    }
                    insert_result = db.games.insert_one(game_record)
                    # Add the ID as string for serialization
                    game_record['_id'] = str(insert_result.inserted_id)
                
                # Publish to RabbitMQ for analytics
                with start_span(op="mq.publish", description="Publish game result to RabbitMQ") as mq_span:
                    try:
                        # Get current trace headers for propagation
                        current_span = sentry_sdk.get_current_span()
                        trace_headers = {
                            'sentry-trace': current_span.to_traceparent() if current_span else '',
                            'baggage': sentry_sdk.get_baggage() or ''
                        }
                        logger.info(f"Publishing with trace headers: {trace_headers}")
                        
                        publisher = get_publisher()
                        publisher.publish_game_result(game_record, trace_headers)
                        
                        mq_span.set_data("mq.queue", "analytics.game_results")
                        mq_span.set_data("mq.routing_key", "game.result")
                        mq_span.set_tag("mq.published", "true")
                        
                    except Exception as mq_error:
                        # Don't fail the request if RabbitMQ is down
                        logger.error(f"Failed to publish to RabbitMQ: {mq_error}")
                        mq_span.set_tag("mq.published", "false")
                        mq_span.set_tag("mq.error", str(mq_error))
                
                # Track business metrics
                with start_span(op="metrics.track", description="Track business metrics") as metric_span:
                    # Track bet and payout volumes
                    BusinessMetrics.track_metric(BusinessMetrics.BET_VOLUME, bet, "currency")
                    BusinessMetrics.track_metric(BusinessMetrics.PAYOUT_VOLUME, payout, "currency")
                    
                    # Track win rate (updated per game)
                    BusinessMetrics.track_metric(BusinessMetrics.WIN_RATE, 100.0 if win else 0.0, "percent")
                    
                    # Calculate and track session RTP
                    session_stats = self._get_session_stats(user_id)
                    if session_stats:
                        session_rtp = BusinessMetrics.track_rtp(
                            session_stats['total_bets'],
                            session_stats['total_payouts'],
                            period="session"
                        )
                        metric_span.set_data("session_rtp", session_rtp)
                    
                    # Track with anomaly detection
                    anomaly_detector = MetricAnomalyDetector()
                    
                    # Calculate 24h rolling RTP
                    rolling_stats = self._get_rolling_stats(24)
                    if rolling_stats:
                        rolling_rtp = BusinessMetrics.track_rtp(
                            rolling_stats['total_bets'],
                            rolling_stats['total_payouts'],
                            period="24h"
                        )
                        anomaly_detector.track_with_anomaly_detection(
                            BusinessMetrics.RTP_ROLLING,
                            rolling_rtp,
                            unit="percent",
                            tags={"period": "24h"}
                        )
                
                # Update user balance and get new balance
                with start_span(op="db.balance", description="Update user balance") as balance_span:
                    new_balance = update_user_balance(user_id, bet, payout)
                    balance_span.set_data("new_balance", new_balance)
                    balance_span.set_data("balance_change", -bet + payout)

                # Integrate with wager-service for bonus tracking
                wager_result = None
                if USE_WAGER_SERVICE:
                    with start_span(op="wager.integrate", description="Update wager service") as wager_span:
                        # Validate wager first
                        validation_data = validate_wager_with_service(user_id, bet, "slot-machine")
                        if validation_data:
                            wager_span.set_data("validation", "success")
                            # Place the wager with result
                            game_result_str = "win" if win else "lose"
                            wager_result = place_wager_with_service(validation_data, game_result_str, payout)
                            if wager_result:
                                wager_span.set_data("wager_id", wager_result.get('wager_id'))
                                wager_span.set_data("wagering_progress", wager_result.get('wagering_progress'))
                        else:
                            wager_span.set_data("validation", "skipped_or_failed")

                # Add custom measurements (legacy)
                sentry_sdk.set_measurement("game.bet_amount", bet)
                sentry_sdk.set_measurement("game.payout", payout)
                sentry_sdk.set_measurement("game.new_balance", new_balance)
                sentry_sdk.set_tag("game.win", str(win))

                response = {
                    "win": win,
                    "payout": payout,
                    "symbols": result['symbols'],
                    "newBalance": new_balance
                }

                # Add wagering progress to response if available
                if wager_result and wager_result.get('wagering_progress'):
                    response['wageringProgress'] = wager_result['wagering_progress']

                self.set_status(200)
                self.write(response)
                
            except Exception as e:
                sentry_sdk.capture_exception(e)
                self.set_status(500)
                self.write({"error": str(e)})
    
    def _calculate_slot_result_normal(self):
        """Normal slot calculation with 90% RTP"""
        symbols = ['🍒', '🍋', '🍊', '🍇', '⭐', '💎']
        
        # Symbol weights for 90% RTP
        # Higher weight = more frequent appearance
        symbol_weights = {
            '🍒': 30,  # 2x multiplier - most frequent
            '🍋': 25,  # 3x multiplier
            '🍊': 20,  # 4x multiplier
            '🍇': 15,  # 5x multiplier
            '⭐': 8,   # 10x multiplier
            '💎': 2    # 20x multiplier - rarest
        }
        
        # Create weighted symbol list
        weighted_symbols = []
        for symbol, weight in symbol_weights.items():
            weighted_symbols.extend([symbol] * weight)
        
        # 90% RTP calculation:
        # Win probability should be ~30% to achieve 90% RTP with average multiplier of 3x
        # 30% win * 3x average multiplier = 90% RTP
        
        # Determine if this spin wins (30% chance)
        is_winning_spin = random.random() < 0.30
        
        if is_winning_spin:
            # For winning spins, select one symbol for all reels
            winning_symbol = random.choice(weighted_symbols)
            result_symbols = [winning_symbol, winning_symbol, winning_symbol]
            win = True
        else:
            # For losing spins, ensure at least one symbol is different
            result_symbols = [random.choice(weighted_symbols) for _ in range(3)]
            # Force a mismatch if accidentally all match
            if result_symbols[0] == result_symbols[1] == result_symbols[2]:
                # Change the middle symbol
                other_symbols = [s for s in symbols if s != result_symbols[0]]
                result_symbols[1] = random.choice(other_symbols)
            win = False
        
        # Calculate multiplier based on symbol
        multipliers = {
            '🍒': 2,
            '🍋': 3,
            '🍊': 4,
            '🍇': 5,
            '⭐': 10,
            '💎': 20
        }
        
        multiplier = multipliers.get(result_symbols[0], 1) if win else 0
        
        return {
            'symbols': result_symbols,
            'win': win,
            'multiplier': multiplier
        }
    
    def _is_prime(self, n):
        """Inefficient prime check for CPU spike demo"""
        if n < 2:
            return False
        for i in range(2, int(n**0.5) + 1):
            if n % i == 0:
                return False
        return True
    
    def _calculate_slot_result_cpu_intensive(self):
        """CPU-intensive calculation with 90% RTP using prime number generation"""
        import time
        start_time = time.time()
        
        with start_span(op="cpu.prime_generation", description="Generate large primes") as span:
            # Generate large prime numbers (VERY inefficient on purpose)
            primes = []
            num = 10000000  # Start with a much larger number for more CPU work
            while len(primes) < 10:  # Generate 10 primes instead of 3
                if self._is_prime(num):
                    primes.append(num)
                num += 1
            span.set_data("primes_generated", len(primes))
            span.set_data("largest_prime", primes[-1])
        
        with start_span(op="cpu.heavy_calculation", description="Heavy math operations") as span:
            # Symbol weights for 90% RTP
            symbol_weights = {
                '🍒': 30,  # 2x multiplier - most frequent
                '🍋': 25,  # 3x multiplier
                '🍊': 20,  # 4x multiplier
                '🍇': 15,  # 5x multiplier
                '⭐': 8,   # 10x multiplier
                '💎': 2    # 20x multiplier - rarest
            }
            
            # Create weighted symbol list
            symbols = ['🍒', '🍋', '🍊', '🍇', '⭐', '💎']
            weighted_symbols = []
            for symbol, weight in symbol_weights.items():
                weighted_symbols.extend([symbol] * weight)
            
            # Do heavy calculations to determine win (30% chance for 90% RTP)
            heavy_calc_sum = 0
            matrix_size = 100  # Add matrix operations
            
            # Create random matrices for multiplication
            matrix_a = np.random.rand(matrix_size, matrix_size)
            matrix_b = np.random.rand(matrix_size, matrix_size)
            
            # Perform multiple matrix multiplications (very CPU intensive)
            with start_span(op="cpu.matrix_operations", description="Matrix multiplications") as matrix_span:
                for _ in range(5):  # 5 matrix multiplications
                    result_matrix = np.matmul(matrix_a, matrix_b)
                    matrix_a = result_matrix  # Use result for next iteration
                matrix_span.set_data("matrix_size", f"{matrix_size}x{matrix_size}")
                matrix_span.set_data("multiplications", 5)
            
            # Continue with prime-based calculations
            for prime in primes:
                # More intensive CPU operations
                for i in range(5000):  # Reduced iterations but with more complex math
                    heavy_calc_sum += np.sin(prime * i) * np.cos(prime / (i + 1))
                    heavy_calc_sum += np.log(abs(heavy_calc_sum) + 1)
                    # Add exponential calculations
                    heavy_calc_sum += np.exp(-abs(heavy_calc_sum) / 1000000)
            
            # Calculate elapsed time
            elapsed_ms = (time.time() - start_time) * 1000
            span.set_data("calculation_time_ms", round(elapsed_ms, 2))
            
            # Use the heavy calculation to determine if this is a winning spin
            # Normalize to 0-1 range and check if < 0.30 for 30% win rate
            win_threshold = abs(heavy_calc_sum) % 100 / 100.0
            is_winning_spin = win_threshold < 0.90
            
            if is_winning_spin:
                # For winning spins, select one symbol for all reels
                # Use prime-based calculation to select symbol
                symbol_selector = int(abs(heavy_calc_sum * primes[0]) % len(weighted_symbols))
                winning_symbol = weighted_symbols[symbol_selector]
                result_symbols = [winning_symbol, winning_symbol, winning_symbol]
                win = True
            else:
                # For losing spins, use different calculations for each reel
                result_symbols = []
                for i, prime in enumerate(primes):
                    # More CPU work for each symbol
                    reel_calc = 0
                    for j in range(5000):
                        reel_calc += np.sin(prime * j * (i + 1))
                        reel_calc += np.cos(prime / (j + 1))
                    
                    symbol_index = int(abs(reel_calc) % len(weighted_symbols))
                    result_symbols.append(weighted_symbols[symbol_index])
                
                # Ensure at least one symbol is different
                if result_symbols[0] == result_symbols[1] == result_symbols[2]:
                    other_symbols = [s for s in symbols if s != result_symbols[0]]
                    result_symbols[1] = random.choice(other_symbols)
                win = False
            
            span.set_data("calculation_iterations", len(primes) * 15000)
            span.set_data("win_threshold", win_threshold)
        
        # Calculate multiplier based on symbol
        multipliers = {
            '🍒': 2,
            '🍋': 3,
            '🍊': 4,
            '🍇': 5,
            '⭐': 10,
            '💎': 20
        }
        
        multiplier = multipliers.get(result_symbols[0], 1) if win else 0
        
        return {
            'symbols': result_symbols,
            'win': win,
            'multiplier': multiplier
        }
    
    def _get_session_stats(self, user_id: str):
        """Get session statistics for RTP calculation"""
        try:
            # Get games from last hour (session)
            one_hour_ago = time.time() - 3600
            pipeline = [
                {
                    "$match": {
                        "user_id": user_id,
                        "timestamp": {"$gte": one_hour_ago}
                    }
                },
                {
                    "$group": {
                        "_id": None,
                        "total_bets": {"$sum": "$bet"},
                        "total_payouts": {"$sum": "$payout"},
                        "game_count": {"$sum": 1}
                    }
                }
            ]
            result = list(db.games.aggregate(pipeline))
            if result:
                return result[0]
        except Exception as e:
            logger.error(f"Error getting session stats: {e}")
        return None
    
    def _get_rolling_stats(self, hours: int):
        """Get rolling statistics for RTP calculation"""
        try:
            cutoff_time = time.time() - (hours * 3600)
            pipeline = [
                {
                    "$match": {
                        "timestamp": {"$gte": cutoff_time}
                    }
                },
                {
                    "$group": {
                        "_id": None,
                        "total_bets": {"$sum": "$bet"},
                        "total_payouts": {"$sum": "$payout"},
                        "game_count": {"$sum": 1},
                        "unique_players": {"$addToSet": "$user_id"}
                    }
                },
                {
                    "$project": {
                        "total_bets": 1,
                        "total_payouts": 1,
                        "game_count": 1,
                        "unique_player_count": {"$size": "$unique_players"}
                    }
                }
            ]
            result = list(db.games.aggregate(pipeline))
            if result:
                return result[0]
        except Exception as e:
            logger.error(f"Error getting rolling stats: {e}")
        return None
    
    def _calculate_slot_result_inefficient(self):
        """Intentionally inefficient calculation for CPU spike demo"""
        # Simulate complex calculation with nested loops
        # This is BAD code for demonstration purposes
        
        symbols = ['🍒', '🍋', '🍊', '🍇', '⭐', '💎']
        result_symbols = []
        
        # Inefficient random selection
        for _ in range(3):
            # Simulate heavy computation
            heavy_calc = 0
            for i in range(100000):  # Intentionally high iteration
                heavy_calc += np.random.random() * np.sin(i) * np.cos(i)
            
            # Select symbol
            symbol_index = int(abs(heavy_calc) % len(symbols))
            result_symbols.append(symbols[symbol_index])
        
        # Check if win (all symbols match)
        win = all(s == result_symbols[0] for s in result_symbols)
        
        # Calculate multiplier based on symbol
        multipliers = {
            '🍒': 2,
            '🍋': 3,
            '🍊': 4,
            '🍇': 5,
            '⭐': 10,
            '💎': 20
        }
        
        multiplier = multipliers.get(result_symbols[0], 1) if win else 0
        
        return {
            'symbols': result_symbols,
            'win': win,
            'multiplier': multiplier
        }

class BusinessMetricsHandler(web.RequestHandler):
    """Endpoint to trigger business metric scenarios"""
    async def post(self):
        # Check for incoming trace headers
        sentry_trace = self.request.headers.get('sentry-trace', '')
        baggage = self.request.headers.get('baggage', '')
        
        # Continue trace if headers present, otherwise create new transaction
        if sentry_trace:
            transaction = sentry_sdk.continue_trace({
                "sentry-trace": sentry_trace,
                "baggage": baggage
            }, op="business.demo", name="business_metrics_scenario")
        else:
            transaction = {
                "op": "business.demo",
                "name": "business_metrics_scenario"
            }
        
        with sentry_sdk.start_transaction(transaction):
            try:
                data = json.loads(self.request.body)
                scenario = data.get('scenario', 'normal')
                
                if scenario == 'rtp_anomaly':
                    # Simulate RTP dropping below threshold
                    with start_span(op="demo.rtp_anomaly", description="Simulate RTP anomaly"):
                        anomaly_detector = MetricAnomalyDetector()
                        # Track abnormally low RTP
                        anomaly_detector.track_with_anomaly_detection(
                            BusinessMetrics.RTP,
                            75.0,  # Below 85% threshold
                            unit="percent",
                            tags={"scenario": "demo", "alert": "critical"}
                        )
                        # Also track high RTP
                        anomaly_detector.track_with_anomaly_detection(
                            BusinessMetrics.RTP,
                            99.5,  # Above 98% threshold
                            unit="percent", 
                            tags={"scenario": "demo", "alert": "warning"}
                        )
                    
                    self.write({"status": "RTP anomaly triggered", "low_rtp": 75.0, "high_rtp": 99.5})
                
                elif scenario == 'session_surge':
                    # Simulate sudden increase in active sessions
                    with start_span(op="demo.session_surge", description="Simulate session surge"):
                        # Normal sessions
                        BusinessMetrics.track_metric(BusinessMetrics.ACTIVE_SESSIONS, 150, "none")
                        # Sudden surge
                        BusinessMetrics.track_metric(BusinessMetrics.ACTIVE_SESSIONS, 850, "none", 
                                                   {"surge": "true", "alert": "info"})
                    
                    self.write({"status": "Session surge triggered", "normal": 150, "surge": 850})
                
                elif scenario == 'win_rate_manipulation':
                    # Simulate suspicious win rate patterns
                    with start_span(op="demo.win_rate", description="Simulate win rate manipulation"):
                        anomaly_detector = MetricAnomalyDetector()
                        # Abnormally high win rate
                        anomaly_detector.track_with_anomaly_detection(
                            BusinessMetrics.WIN_RATE,
                            85.0,  # Way above 50% threshold
                            unit="percent",
                            tags={"scenario": "demo", "alert": "critical", "fraud_risk": "high"}
                        )
                    
                    self.write({"status": "Win rate anomaly triggered", "suspicious_rate": 85.0})
                
                else:
                    # Normal metrics
                    with start_span(op="demo.normal", description="Normal business metrics"):
                        BusinessMetrics.track_metric(BusinessMetrics.RTP, 95.5, "percent")
                        BusinessMetrics.track_metric(BusinessMetrics.WIN_RATE, 35.0, "percent")
                        BusinessMetrics.track_metric(BusinessMetrics.ACTIVE_SESSIONS, 250, "none")
                    
                    self.write({"status": "Normal metrics tracked"})
                
                self.set_status(200)
                
            except Exception as e:
                sentry_sdk.capture_exception(e)
                self.set_status(500)
                self.write({"error": str(e)})

class DebugCrashHandler(web.RequestHandler):
    """Trigger various types of crashes for Sentry demo"""
    
    async def get(self):
        """Unhandled exception demo"""
        # Add breadcrumbs to track user actions
        sentry_sdk.add_breadcrumb(
            message="User accessed debug crash endpoint",
            category="debug",
            level="info",
            data={
                "endpoint": self.request.path,
                "method": self.request.method,
                "user_ip": self.request.remote_ip
            }
        )
        
        # Set user context
        sentry_sdk.set_user({
            "id": "debug-user",
            "ip_address": self.request.remote_ip
        })
        
        # Add custom context about system state
        process = psutil.Process()
        sentry_sdk.set_context("runtime", {
            "memory_mb": process.memory_info().rss / 1024 / 1024,
            "cpu_percent": process.cpu_percent(interval=0.1),
            "threads": process.num_threads(),
            "python_version": os.sys.version,
            "tornado_version": tornado.version
        })
        
        # Trigger crash
        raise RuntimeError("[DEMO] Game Engine crash triggered! This demonstrates Python error tracking with rich context.")
    
class DebugErrorHandler(web.RequestHandler):
    """Trigger different error types"""
    
    async def get(self, error_type):
        """Trigger specific error types"""
        # Add breadcrumb
        sentry_sdk.add_breadcrumb(
            message=f"Triggering {error_type} error",
            category="debug",
            level="warning",
            data={"error_type": error_type}
        )
        
        # Set tags for error grouping
        sentry_sdk.set_tag("error.type", error_type)
        sentry_sdk.set_tag("debug.demo", "true")
        
        if error_type == "value":
            # ValueError demo
            invalid_data = "not_a_number"
            sentry_sdk.add_breadcrumb(
                message="Attempting to convert invalid data",
                category="debug",
                data={"value": invalid_data}
            )
            int(invalid_data)  # This will raise ValueError
            
        elif error_type == "type":
            # TypeError demo
            data = {"key": "value"}
            sentry_sdk.add_breadcrumb(
                message="Attempting invalid operation",
                category="debug", 
                data={"operation": "len() on dict"}
            )
            len(data())  # This will raise TypeError
            
        elif error_type == "index":
            # IndexError demo
            items = [1, 2, 3]
            sentry_sdk.add_breadcrumb(
                message="Accessing out of bounds index",
                category="debug",
                data={"list_length": len(items), "accessing_index": 10}
            )
            return items[10]  # This will raise IndexError
            
        elif error_type == "key":
            # KeyError demo
            data = {"name": "test"}
            sentry_sdk.add_breadcrumb(
                message="Accessing missing dictionary key",
                category="debug",
                data={"available_keys": list(data.keys()), "requested_key": "missing"}
            )
            return data["missing"]  # This will raise KeyError
            
        elif error_type == "zero":
            # ZeroDivisionError demo
            numerator = 100
            denominator = 0
            sentry_sdk.add_breadcrumb(
                message="Attempting division by zero",
                category="debug",
                data={"numerator": numerator, "denominator": denominator}
            )
            return numerator / denominator  # This will raise ZeroDivisionError
            
        elif error_type == "custom":
            # Custom exception with extra context
            class GameEngineError(Exception):
                """Custom game engine error"""
                def __init__(self, message, error_code, context):
                    super().__init__(message)
                    self.error_code = error_code
                    self.context = context
            
            raise GameEngineError(
                "Custom game engine error for demo",
                error_code="GAME_001",
                context={"game_state": "active", "session_id": "12345"}
            )
        
        else:
            self.set_status(400)
            self.write({"error": f"Unknown error type: {error_type}"})
            
class DebugMemoryLeakHandler(web.RequestHandler):
    """Simulate memory leak"""
    _memory_leak = []  # Class variable to persist between requests
    
    async def get(self):
        """Create memory leak by accumulating data"""
        # Add breadcrumb
        sentry_sdk.add_breadcrumb(
            message="Starting memory leak simulation",
            category="debug.memory",
            level="warning",
            data={"initial_items": len(self._memory_leak)}
        )
        
        # Get initial memory
        process = psutil.Process()
        initial_memory = process.memory_info().rss / 1024 / 1024
        
        # Create memory leak - allocate 10MB of data
        leak_size = 10 * 1024 * 1024  # 10MB
        data = 'X' * leak_size
        self._memory_leak.append(data)
        
        # Force some CPU usage while we're at it
        for _ in range(1000000):
            hash(data)
        
        # Get final memory
        final_memory = process.memory_info().rss / 1024 / 1024
        memory_increase = final_memory - initial_memory
        
        # Log memory growth
        sentry_sdk.set_context("memory_leak", {
            "initial_memory_mb": initial_memory,
            "final_memory_mb": final_memory,
            "increase_mb": memory_increase,
            "total_leaked_items": len(self._memory_leak),
            "total_leaked_mb": len(self._memory_leak) * 10
        })
        
        # Capture a message about the leak
        sentry_sdk.capture_message(
            f"Memory leak demo: {memory_increase:.2f}MB increase, total leaked: {len(self._memory_leak) * 10}MB",
            level="warning"
        )
        
        self.write({
            "status": "Memory leak created",
            "memory_increase_mb": memory_increase,
            "total_leaked_mb": len(self._memory_leak) * 10,
            "current_memory_mb": final_memory
        })
        
class DebugInfiniteLoopHandler(web.RequestHandler):
    """Simulate infinite loop / CPU spike"""
    
    async def get(self):
        """Create CPU spike with infinite calculation"""
        # Add breadcrumb
        sentry_sdk.add_breadcrumb(
            message="Starting infinite loop simulation",
            category="debug.cpu",
            level="error",
            data={"warning": "This will spike CPU for 5 seconds"}
        )
        
        # Set context
        process = psutil.Process()
        sentry_sdk.set_context("cpu_spike", {
            "initial_cpu": process.cpu_percent(interval=0.1),
            "threads": process.num_threads()
        })
        
        # Run CPU-intensive loop for 5 seconds
        start_time = time.time()
        iterations = 0
        
        while time.time() - start_time < 5:
            # Intensive calculations
            for i in range(10000):
                _ = sum(j**2 for j in range(100))
                _ = [np.sin(i) * np.cos(i) for _ in range(10)]
            iterations += 10000
            
            # Yield control briefly to avoid blocking
            if iterations % 100000 == 0:
                await asyncio.sleep(0.001)
        
        # Capture metrics
        final_cpu = process.cpu_percent(interval=0.1)
        sentry_sdk.capture_message(
            f"CPU spike demo completed: {iterations:,} iterations, CPU: {final_cpu}%",
            level="warning"
        )
        
        self.write({
            "status": "CPU spike completed",
            "duration_seconds": 5,
            "iterations": iterations,
            "final_cpu_percent": final_cpu
        })
        
class DebugAsyncErrorHandler(web.RequestHandler):
    """Demonstrate async/await error handling"""
    
    async def get(self):
        """Trigger async errors"""
        # Add breadcrumb
        sentry_sdk.add_breadcrumb(
            message="Starting async error demo",
            category="debug.async",
            level="info"
        )
        
        try:
            # Create multiple async tasks with errors
            tasks = [
                self._async_task_success(),
                self._async_task_failure(),
                self._async_task_timeout()
            ]
            
            # Wait for all tasks (some will fail)
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Process results
            for i, result in enumerate(results):
                if isinstance(result, Exception):
                    sentry_sdk.capture_exception(result)
                    
        except Exception as e:
            sentry_sdk.capture_exception(e)
            raise
            
    async def _async_task_success(self):
        """Successful async task"""
        await asyncio.sleep(0.1)
        return "Success"
        
    async def _async_task_failure(self):
        """Failing async task"""
        await asyncio.sleep(0.2)
        raise RuntimeError("Async task failed in coroutine")
        
    async def _async_task_timeout(self):
        """Timeout async task"""
        try:
            # This will timeout
            await asyncio.wait_for(asyncio.sleep(10), timeout=0.5)
        except asyncio.TimeoutError as e:
            # Re-raise with more context
            raise RuntimeError("Async operation timed out after 500ms") from e

class DebugThreadingErrorHandler(web.RequestHandler):
    """Demonstrate threading errors"""
    
    def get(self):
        """Trigger threading errors"""
        # Add breadcrumb
        sentry_sdk.add_breadcrumb(
            message="Starting threading error demo",
            category="debug.threading",
            level="warning"
        )
        
        # Create threads that will have errors
        threads = []
        
        def thread_with_error(thread_id):
            """Thread that will crash"""
            try:
                # Set thread-local context
                sentry_sdk.set_tag("thread.id", str(thread_id))
                sentry_sdk.add_breadcrumb(
                    message=f"Thread {thread_id} started",
                    category="thread"
                )
                
                # Simulate some work
                time.sleep(0.1 * thread_id)
                
                # Trigger error
                if thread_id == 2:
                    raise ValueError(f"Thread {thread_id} encountered an error")
                    
            except Exception as e:
                # Capture in thread context
                sentry_sdk.capture_exception(e)
                
        # Start multiple threads
        for i in range(3):
            thread = threading.Thread(target=thread_with_error, args=(i,))
            thread.start()
            threads.append(thread)
            
        # Wait for threads
        for thread in threads:
            thread.join()
            
        self.write({
            "status": "Threading demo completed",
            "threads_created": len(threads)
        })

def make_app():
    return web.Application([
        (r"/health", HealthHandler),
        (r"/metrics", MetricsHandler),
        (r"/calculate", CalculateHandler),
        (r"/business-metrics", BusinessMetricsHandler),
        # Debug endpoints
        (r"/debug/crash", DebugCrashHandler),
        (r"/debug/error/(.*)", DebugErrorHandler),
        (r"/debug/memory-leak", DebugMemoryLeakHandler),
        (r"/debug/infinite-loop", DebugInfiniteLoopHandler),
        (r"/debug/async-error", DebugAsyncErrorHandler),
        (r"/debug/threading-error", DebugThreadingErrorHandler),
    ])

if __name__ == "__main__":
    app = make_app()
    app.listen(8082)
    print("Game Engine started on :8082")
    ioloop.IOLoop.current().start()