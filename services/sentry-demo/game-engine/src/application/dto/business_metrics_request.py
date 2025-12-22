"""Business metrics request DTO"""
from dataclasses import dataclass
from typing import Optional


@dataclass
class BusinessMetricsRequest:
    """Request DTO for business metrics tracking"""

    scenario: str = "normal"

    @classmethod
    def from_dict(cls, data: dict) -> 'BusinessMetricsRequest':
        """Create from dictionary"""
        return cls(
            scenario=data.get('scenario', 'normal')
        )
