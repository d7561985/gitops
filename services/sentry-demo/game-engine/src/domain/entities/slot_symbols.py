"""Slot machine symbols configuration"""
from dataclasses import dataclass
from typing import Dict, List


@dataclass
class SlotSymbols:
    """Slot machine symbol configuration with weights and multipliers"""

    SYMBOLS: List[str] = None
    WEIGHTS: Dict[str, int] = None
    MULTIPLIERS: Dict[str, int] = None

    def __post_init__(self):
        self.SYMBOLS = ['🍒', '🍋', '🍊', '🍇', '⭐', '💎']

        # Symbol weights for 90% RTP
        self.WEIGHTS = {
            '🍒': 30,  # 2x multiplier - most frequent
            '🍋': 25,  # 3x multiplier
            '🍊': 20,  # 4x multiplier
            '🍇': 15,  # 5x multiplier
            '⭐': 8,   # 10x multiplier
            '💎': 2    # 20x multiplier - rarest
        }

        self.MULTIPLIERS = {
            '🍒': 2,
            '🍋': 3,
            '🍊': 4,
            '🍇': 5,
            '⭐': 10,
            '💎': 20
        }

    def get_weighted_symbols(self) -> List[str]:
        """Create weighted symbol list for random selection"""
        weighted = []
        for symbol, weight in self.WEIGHTS.items():
            weighted.extend([symbol] * weight)
        return weighted

    def get_multiplier(self, symbol: str) -> int:
        """Get payout multiplier for a symbol"""
        return self.MULTIPLIERS.get(symbol, 1)
