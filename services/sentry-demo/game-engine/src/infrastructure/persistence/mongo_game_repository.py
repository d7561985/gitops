"""MongoDB game repository implementation"""
import time
import logging
from typing import Optional, Dict, Any
from pymongo import MongoClient
from pymongo.database import Database

from src.domain.entities.game_result import GameResult
from src.application.ports.game_repository_port import GameRepositoryPort

logger = logging.getLogger(__name__)


class MongoGameRepository(GameRepositoryPort):
    """MongoDB implementation of game repository"""

    def __init__(self, db: Database):
        self.db = db
        self.collection = db.games

    def save(self, game: GameResult) -> GameResult:
        """Save game result to MongoDB"""
        data = {
            "user_id": game.user_id,
            "bet": game.bet,
            "symbols": game.symbols,
            "win": game.win,
            "multiplier": game.multiplier,
            "payout": game.payout,
            "timestamp": game.timestamp
        }
        result = self.collection.insert_one(data)
        game.id = str(result.inserted_id)
        return game

    def get_session_stats(self, user_id: str, hours: int = 1) -> Optional[Dict[str, Any]]:
        """Get session statistics for RTP calculation"""
        try:
            cutoff_time = time.time() - (hours * 3600)
            pipeline = [
                {
                    "$match": {
                        "user_id": user_id,
                        "timestamp": {"$gte": cutoff_time}
                    }
                },
                {
                    "$group": {
                        "_id": None,
                        "total_bets": {"$sum": "$bet"},
                        "total_payouts": {"$sum": "$payout"},
                        "game_count": {"$sum": 1}
                    }
                }
            ]
            result = list(self.collection.aggregate(pipeline))
            return result[0] if result else None
        except Exception as e:
            logger.error(f"Error getting session stats: {e}")
            return None

    def get_rolling_stats(self, hours: int = 24) -> Optional[Dict[str, Any]]:
        """Get rolling statistics across all users"""
        try:
            cutoff_time = time.time() - (hours * 3600)
            pipeline = [
                {
                    "$match": {
                        "timestamp": {"$gte": cutoff_time}
                    }
                },
                {
                    "$group": {
                        "_id": None,
                        "total_bets": {"$sum": "$bet"},
                        "total_payouts": {"$sum": "$payout"},
                        "game_count": {"$sum": 1},
                        "unique_players": {"$addToSet": "$user_id"}
                    }
                },
                {
                    "$project": {
                        "total_bets": 1,
                        "total_payouts": 1,
                        "game_count": 1,
                        "unique_player_count": {"$size": "$unique_players"}
                    }
                }
            ]
            result = list(self.collection.aggregate(pipeline))
            return result[0] if result else None
        except Exception as e:
            logger.error(f"Error getting rolling stats: {e}")
            return None
