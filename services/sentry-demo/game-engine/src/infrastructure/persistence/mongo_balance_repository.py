"""MongoDB balance repository implementation"""
import os
import time
import logging
from pymongo import ReturnDocument
from pymongo.database import Database

from src.application.ports.balance_repository_port import BalanceRepositoryPort

logger = logging.getLogger(__name__)


class MongoBalanceRepository(BalanceRepositoryPort):
    """MongoDB implementation of balance repository"""

    def __init__(self, db: Database, default_balance: float = None):
        self.db = db
        self.collection = db.user_balances
        self.default_balance = default_balance or float(os.environ.get('DEFAULT_BALANCE', '1000'))

    def get_balance(self, user_id: str) -> float:
        """Get user balance from MongoDB"""
        user = self.collection.find_one({"user_id": user_id})
        if user:
            return user.get('balance', self.default_balance)

        # Create new user with default balance
        self.collection.insert_one({
            "user_id": user_id,
            "balance": self.default_balance,
            "created_at": time.time()
        })
        return self.default_balance

    def update_balance(self, user_id: str, bet: float, payout: float) -> float:
        """Update user balance and return new balance"""
        result = self.collection.find_one_and_update(
            {"user_id": user_id},
            {
                "$inc": {"balance": -bet + payout},
                "$set": {"updated_at": time.time()}
            },
            upsert=True,
            return_document=ReturnDocument.AFTER
        )

        # Handle case where user didn't exist
        if result.get('balance') is None or result.get('balance') < 0:
            new_balance = self.default_balance - bet + payout
            self.collection.update_one(
                {"user_id": user_id},
                {"$set": {"balance": new_balance}}
            )
            return new_balance

        return result.get('balance', self.default_balance)
