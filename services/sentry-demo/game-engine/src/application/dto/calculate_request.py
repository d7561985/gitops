"""Calculate game result request DTO"""
from dataclasses import dataclass
from typing import Optional


@dataclass
class CalculateRequest:
    """Request DTO for game calculation"""

    user_id: str
    bet: float
    cpu_intensive: bool = False

    @classmethod
    def from_dict(cls, data: dict) -> 'CalculateRequest':
        """Create from dictionary (Connect protocol)"""
        return cls(
            user_id=data.get('userId', ''),
            bet=float(data.get('bet', 0)),
            cpu_intensive=data.get('cpuIntensive', False)
        )

    @classmethod
    def from_snake_case(cls, data: dict) -> 'CalculateRequest':
        """Create from snake_case dictionary (REST API)"""
        return cls(
            user_id=data.get('user_id', ''),
            bet=float(data.get('bet', 0)),
            cpu_intensive=data.get('cpu_intensive', False)
        )
