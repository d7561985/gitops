"""Game result entity"""
from dataclasses import dataclass, field
from typing import List, Optional
import time


@dataclass
class GameResult:
    """Domain entity representing a game (slot) result"""

    user_id: str
    bet: float
    symbols: List[str]
    win: bool
    multiplier: int
    payout: float
    timestamp: float = field(default_factory=time.time)
    id: Optional[str] = None

    @property
    def balance_change(self) -> float:
        """Calculate net balance change"""
        return -self.bet + self.payout

    def to_dict(self) -> dict:
        """Convert to dictionary for storage"""
        return {
            "user_id": self.user_id,
            "bet": self.bet,
            "symbols": self.symbols,
            "win": self.win,
            "multiplier": self.multiplier,
            "payout": self.payout,
            "timestamp": self.timestamp,
            "_id": self.id
        }

    @classmethod
    def from_dict(cls, data: dict) -> 'GameResult':
        """Create from dictionary"""
        return cls(
            user_id=data.get("user_id"),
            bet=data.get("bet", 0),
            symbols=data.get("symbols", []),
            win=data.get("win", False),
            multiplier=data.get("multiplier", 0),
            payout=data.get("payout", 0),
            timestamp=data.get("timestamp", time.time()),
            id=str(data.get("_id")) if data.get("_id") else None
        )
