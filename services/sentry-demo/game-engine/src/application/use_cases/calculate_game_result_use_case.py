"""Calculate game result use case"""
import random
import logging
from typing import Dict, Any, Optional
import numpy as np
import sentry_sdk
from sentry_sdk import start_span

from src.domain.entities.game_result import GameResult
from src.domain.entities.slot_symbols import SlotSymbols
from src.application.dto.calculate_request import CalculateRequest
from src.application.dto.calculate_response import CalculateResponse
from src.application.ports.game_repository_port import GameRepositoryPort
from src.application.ports.balance_repository_port import BalanceRepositoryPort
from src.application.ports.message_publisher_port import MessagePublisherPort
from src.application.ports.wager_service_port import WagerServicePort

logger = logging.getLogger(__name__)


class CalculateGameResultUseCase:
    """Use case for calculating slot game results"""

    def __init__(
        self,
        game_repository: GameRepositoryPort,
        balance_repository: BalanceRepositoryPort,
        message_publisher: MessagePublisherPort,
        wager_service: Optional[WagerServicePort] = None
    ):
        self.game_repository = game_repository
        self.balance_repository = balance_repository
        self.message_publisher = message_publisher
        self.wager_service = wager_service
        self.slot_symbols = SlotSymbols()

    def execute(self, request: CalculateRequest, trace_headers: Optional[Dict[str, str]] = None) -> CalculateResponse:
        """Execute game calculation"""
        try:
            # Calculate slot result
            with start_span(op="game.rng", description="Calculate slot result") as span:
                if request.cpu_intensive:
                    result = self._calculate_cpu_intensive()
                    span.set_data("calculation_method", "cpu_intensive")
                    span.set_tag("performance.issue", "cpu_spike")
                else:
                    result = self._calculate_normal()
                    span.set_data("calculation_method", "normal")

            # Calculate payout
            payout = request.bet * result['multiplier'] if result['win'] else 0

            # Create domain entity
            game = GameResult(
                user_id=request.user_id,
                bet=request.bet,
                symbols=result['symbols'],
                win=result['win'],
                multiplier=result['multiplier'],
                payout=payout
            )

            # Persist game result
            with start_span(op="db.insert", description="Store game result") as span:
                span.set_data("db.system", "mongodb")
                span.set_data("db.collection", "games")
                saved_game = self.game_repository.save(game)

            # Publish to message queue
            with start_span(op="mq.publish", description="Publish game result") as mq_span:
                try:
                    self.message_publisher.publish_game_result(
                        saved_game.to_dict(),
                        trace_headers or {}
                    )
                    mq_span.set_tag("mq.published", "true")
                except Exception as mq_error:
                    logger.error(f"Failed to publish to RabbitMQ: {mq_error}")
                    mq_span.set_tag("mq.published", "false")
                    mq_span.set_tag("mq.error", str(mq_error))

            # Track business metrics
            with start_span(op="metrics.track", description="Track business metrics"):
                self._track_metrics(request.user_id, request.bet, payout, result['win'])

            # Update balance
            with start_span(op="db.balance", description="Update user balance") as balance_span:
                new_balance = self.balance_repository.update_balance(
                    request.user_id, request.bet, payout
                )
                balance_span.set_data("new_balance", new_balance)
                balance_span.set_data("balance_change", game.balance_change)

            # Integrate with wager service (bonus tracking)
            wagering_progress = None
            if self.wager_service:
                with start_span(op="wager.integrate", description="Update wager service") as wager_span:
                    validation_data = self.wager_service.validate_wager(
                        request.user_id, request.bet, "slot-machine"
                    )
                    if validation_data:
                        wager_span.set_data("validation", "success")
                        game_result_str = "win" if result['win'] else "lose"
                        wager_result = self.wager_service.place_wager(
                            validation_data, game_result_str, payout
                        )
                        if wager_result:
                            wager_span.set_data("wager_id", wager_result.get('wager_id'))
                            wagering_progress = wager_result.get('wagering_progress')
                    else:
                        wager_span.set_data("validation", "skipped_or_failed")

            # Add Sentry measurements
            sentry_sdk.set_measurement("game.bet_amount", request.bet)
            sentry_sdk.set_measurement("game.payout", payout)
            sentry_sdk.set_measurement("game.new_balance", new_balance)
            sentry_sdk.set_tag("game.win", str(result['win']))

            return CalculateResponse(
                win=result['win'],
                payout=payout,
                symbols=result['symbols'],
                new_balance=new_balance,
                wagering_progress=wagering_progress
            )

        except Exception as e:
            sentry_sdk.capture_exception(e)
            return CalculateResponse(
                win=False,
                payout=0,
                symbols=[],
                new_balance=0,
                error=str(e)
            )

    def _calculate_normal(self) -> Dict[str, Any]:
        """Normal slot calculation with 90% RTP"""
        weighted_symbols = self.slot_symbols.get_weighted_symbols()

        # 30% win chance for ~90% RTP (30% * 3x avg multiplier)
        is_winning = random.random() < 0.30

        if is_winning:
            winning_symbol = random.choice(weighted_symbols)
            result_symbols = [winning_symbol, winning_symbol, winning_symbol]
        else:
            result_symbols = [random.choice(weighted_symbols) for _ in range(3)]
            # Ensure no accidental win
            if result_symbols[0] == result_symbols[1] == result_symbols[2]:
                other_symbols = [s for s in self.slot_symbols.SYMBOLS if s != result_symbols[0]]
                result_symbols[1] = random.choice(other_symbols)

        multiplier = self.slot_symbols.get_multiplier(result_symbols[0]) if is_winning else 0

        return {
            'symbols': result_symbols,
            'win': is_winning,
            'multiplier': multiplier
        }

    def _calculate_cpu_intensive(self) -> Dict[str, Any]:
        """CPU-intensive calculation for demo"""
        import time
        start_time = time.time()

        with start_span(op="cpu.prime_generation", description="Generate large primes") as span:
            primes = []
            num = 10000000
            while len(primes) < 10:
                if self._is_prime(num):
                    primes.append(num)
                num += 1
            span.set_data("primes_generated", len(primes))

        with start_span(op="cpu.matrix_operations", description="Matrix multiplications") as span:
            matrix_size = 100
            matrix_a = np.random.rand(matrix_size, matrix_size)
            matrix_b = np.random.rand(matrix_size, matrix_size)
            for _ in range(5):
                matrix_a = np.matmul(matrix_a, matrix_b)
            span.set_data("matrix_size", f"{matrix_size}x{matrix_size}")

        with start_span(op="cpu.heavy_calculation", description="Heavy math") as span:
            heavy_calc_sum = 0
            for prime in primes:
                for i in range(5000):
                    heavy_calc_sum += np.sin(prime * i) * np.cos(prime / (i + 1))
                    heavy_calc_sum += np.log(abs(heavy_calc_sum) + 1)
                    heavy_calc_sum += np.exp(-abs(heavy_calc_sum) / 1000000)

            elapsed_ms = (time.time() - start_time) * 1000
            span.set_data("calculation_time_ms", round(elapsed_ms, 2))

            weighted_symbols = self.slot_symbols.get_weighted_symbols()
            win_threshold = abs(heavy_calc_sum) % 100 / 100.0
            is_winning = win_threshold < 0.30

            if is_winning:
                symbol_index = int(abs(heavy_calc_sum * primes[0]) % len(weighted_symbols))
                winning_symbol = weighted_symbols[symbol_index]
                result_symbols = [winning_symbol, winning_symbol, winning_symbol]
            else:
                result_symbols = []
                for i, prime in enumerate(primes[:3]):
                    reel_calc = sum(np.sin(prime * j * (i + 1)) for j in range(5000))
                    symbol_index = int(abs(reel_calc) % len(weighted_symbols))
                    result_symbols.append(weighted_symbols[symbol_index])

                if result_symbols[0] == result_symbols[1] == result_symbols[2]:
                    other = [s for s in self.slot_symbols.SYMBOLS if s != result_symbols[0]]
                    result_symbols[1] = random.choice(other)

        multiplier = self.slot_symbols.get_multiplier(result_symbols[0]) if is_winning else 0

        return {
            'symbols': result_symbols,
            'win': is_winning,
            'multiplier': multiplier
        }

    def _is_prime(self, n: int) -> bool:
        """Check if number is prime (inefficient for demo)"""
        if n < 2:
            return False
        for i in range(2, int(n ** 0.5) + 1):
            if n % i == 0:
                return False
        return True

    def _track_metrics(self, user_id: str, bet: float, payout: float, win: bool):
        """Track business metrics"""
        from metrics import BusinessMetrics, MetricAnomalyDetector

        BusinessMetrics.track_metric(BusinessMetrics.BET_VOLUME, bet, "currency")
        BusinessMetrics.track_metric(BusinessMetrics.PAYOUT_VOLUME, payout, "currency")
        BusinessMetrics.track_metric(BusinessMetrics.WIN_RATE, 100.0 if win else 0.0, "percent")

        # Track session RTP
        session_stats = self.game_repository.get_session_stats(user_id, hours=1)
        if session_stats:
            BusinessMetrics.track_rtp(
                session_stats['total_bets'],
                session_stats['total_payouts'],
                period="session"
            )

        # Track rolling RTP with anomaly detection
        rolling_stats = self.game_repository.get_rolling_stats(hours=24)
        if rolling_stats:
            rolling_rtp = BusinessMetrics.track_rtp(
                rolling_stats['total_bets'],
                rolling_stats['total_payouts'],
                period="24h"
            )
            MetricAnomalyDetector().track_with_anomaly_detection(
                BusinessMetrics.RTP_ROLLING,
                rolling_rtp,
                unit="percent",
                tags={"period": "24h"}
            )
