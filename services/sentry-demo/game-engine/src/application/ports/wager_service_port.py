"""Wager service integration port (interface)"""
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any


class WagerServicePort(ABC):
    """Port for wager service integration (bonus tracking)"""

    @abstractmethod
    def validate_wager(self, user_id: str, bet: float, game_id: str = "slot-machine") -> Optional[Dict[str, Any]]:
        """Validate wager before processing spin"""
        pass

    @abstractmethod
    def place_wager(self, validation_data: Dict[str, Any], game_result: str, payout: float) -> Optional[Dict[str, Any]]:
        """Place wager after spin completes"""
        pass
