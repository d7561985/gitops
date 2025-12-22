"""Message publisher port (interface)"""
from abc import ABC, abstractmethod
from typing import Dict, Any


class MessagePublisherPort(ABC):
    """Port for publishing game events"""

    @abstractmethod
    def publish_game_result(self, game_data: Dict[str, Any], trace_headers: Dict[str, str]) -> None:
        """Publish game result for analytics"""
        pass
