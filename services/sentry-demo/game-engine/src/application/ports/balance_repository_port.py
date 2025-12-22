"""Balance repository port (interface)"""
from abc import ABC, abstractmethod


class BalanceRepositoryPort(ABC):
    """Port for user balance management"""

    @abstractmethod
    def get_balance(self, user_id: str) -> float:
        """Get user balance"""
        pass

    @abstractmethod
    def update_balance(self, user_id: str, bet: float, payout: float) -> float:
        """Update user balance after game, returns new balance"""
        pass
