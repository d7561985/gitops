"""HTTP client for wager service integration"""
import os
import logging
import requests
from typing import Dict, Any, Optional

from src.application.ports.wager_service_port import WagerServicePort

logger = logging.getLogger(__name__)


class HttpWagerService(WagerServicePort):
    """HTTP implementation of wager service integration"""

    def __init__(self, base_url: str = None):
        self.base_url = base_url or os.environ.get(
            'WAGER_SERVICE_URL', 'http://sentry-wager-sv:8085'
        )
        self.timeout = 5

    def validate_wager(self, user_id: str, bet: float, game_id: str = "slot-machine") -> Optional[Dict[str, Any]]:
        """Validate wager with wager-service before processing spin"""
        try:
            response = requests.post(
                f"{self.base_url}/wager/validate",
                json={
                    "user_id": user_id,
                    "amount": bet,
                    "game_id": game_id
                },
                timeout=self.timeout
            )
            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"Wager validation failed: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            logger.error(f"Failed to validate wager: {e}")
            return None

    def place_wager(self, validation_data: Dict[str, Any], game_result: str, payout: float) -> Optional[Dict[str, Any]]:
        """Place wager with wager-service after spin completes"""
        try:
            response = requests.post(
                f"{self.base_url}/wager/place",
                json={
                    "validation_data": validation_data,
                    "game_result": game_result,
                    "payout": payout
                },
                timeout=self.timeout
            )
            if response.status_code == 200:
                result = response.json()
                logger.info(f"Wager placed successfully: {result.get('wager_id')}")
                return result
            else:
                logger.warning(f"Wager placement failed: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            logger.error(f"Failed to place wager: {e}")
            return None
