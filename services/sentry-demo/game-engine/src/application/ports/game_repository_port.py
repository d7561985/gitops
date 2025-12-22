"""Game repository port (interface)"""
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
from src.domain.entities.game_result import GameResult


class GameRepositoryPort(ABC):
    """Port for game result persistence"""

    @abstractmethod
    def save(self, game: GameResult) -> GameResult:
        """Save game result, returns game with ID"""
        pass

    @abstractmethod
    def get_session_stats(self, user_id: str, hours: int = 1) -> Optional[Dict[str, Any]]:
        """Get session statistics for RTP calculation"""
        pass

    @abstractmethod
    def get_rolling_stats(self, hours: int = 24) -> Optional[Dict[str, Any]]:
        """Get rolling statistics across all users"""
        pass
