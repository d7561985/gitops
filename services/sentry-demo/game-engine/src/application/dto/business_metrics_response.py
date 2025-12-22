"""Business metrics response DTO"""
from dataclasses import dataclass
from typing import Optional, Dict, Any


@dataclass
class BusinessMetricsResponse:
    """Response DTO for business metrics tracking"""

    status: str
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None

    def to_dict(self) -> dict:
        """Convert to dictionary"""
        result = {"status": self.status}
        if self.data:
            result.update(self.data)
        if self.error:
            result["error"] = self.error
        return result
