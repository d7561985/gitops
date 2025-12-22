"""Dependency Injection Container"""
import os
from pymongo import MongoClient

from src.infrastructure.persistence.mongo_game_repository import MongoGameRepository
from src.infrastructure.persistence.mongo_balance_repository import MongoBalanceRepository
from src.infrastructure.messaging.rabbitmq_message_publisher import RabbitMQMessagePublisher
from src.infrastructure.external.http_wager_service import HttpWagerService
from src.application.use_cases.calculate_game_result_use_case import CalculateGameResultUseCase
from src.application.use_cases.track_business_metrics_use_case import TrackBusinessMetricsUseCase


class Container:
    """Simple DI Container for game engine"""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self):
        """Initialize all dependencies"""
        # MongoDB connection
        mongo_url = os.environ.get('MONGODB_URL', 'mongodb://admin:password@localhost:27017')
        self.mongo_client = MongoClient(mongo_url)
        self.db = self.mongo_client.sentry_poc

        # Repositories
        self.game_repository = MongoGameRepository(self.db)
        self.balance_repository = MongoBalanceRepository(self.db)

        # Message publisher
        self.message_publisher = RabbitMQMessagePublisher()

        # External services (optional)
        use_wager_service = os.environ.get('USE_WAGER_SERVICE', 'false').lower() == 'true'
        self.wager_service = HttpWagerService() if use_wager_service else None

        # Use cases
        self.calculate_use_case = CalculateGameResultUseCase(
            game_repository=self.game_repository,
            balance_repository=self.balance_repository,
            message_publisher=self.message_publisher,
            wager_service=self.wager_service
        )

        self.metrics_use_case = TrackBusinessMetricsUseCase()

    @classmethod
    def get_instance(cls) -> 'Container':
        """Get singleton instance"""
        return cls()

    def get_calculate_use_case(self) -> CalculateGameResultUseCase:
        """Get calculate game result use case"""
        return self.calculate_use_case

    def get_metrics_use_case(self) -> TrackBusinessMetricsUseCase:
        """Get track business metrics use case"""
        return self.metrics_use_case
