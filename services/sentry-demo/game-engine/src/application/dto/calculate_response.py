"""Calculate game result response DTO"""
from dataclasses import dataclass
from typing import List, Optional, Dict, Any


@dataclass
class CalculateResponse:
    """Response DTO for game calculation"""

    win: bool
    payout: float
    symbols: List[str]
    new_balance: float
    wagering_progress: Optional[Dict[str, Any]] = None
    error: Optional[str] = None

    def to_dict(self) -> dict:
        """Convert to camelCase dictionary (Connect protocol)"""
        result = {
            "win": self.win,
            "payout": self.payout,
            "symbols": self.symbols,
            "newBalance": self.new_balance
        }
        if self.wagering_progress:
            result["wageringProgress"] = self.wagering_progress
        if self.error:
            result["error"] = self.error
        return result

    def to_snake_case(self) -> dict:
        """Convert to snake_case dictionary (REST API)"""
        result = {
            "win": self.win,
            "payout": self.payout,
            "symbols": self.symbols,
            "new_balance": self.new_balance
        }
        if self.wagering_progress:
            result["wagering_progress"] = self.wagering_progress
        if self.error:
            result["error"] = self.error
        return result
