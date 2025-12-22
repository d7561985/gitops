/**
 * MongoDB Transaction Repository
 * Implements TransactionRepositoryPort
 */
class MongoTransactionRepository {
  /**
   * @param {Db} db - MongoDB database instance
   */
  constructor(db) {
    this.collection = db.collection('transactions');
  }

  /**
   * Create a new transaction
   * @param {Transaction} transaction
   * @returns {Promise<Transaction>}
   */
  async create(transaction) {
    const result = await this.collection.insertOne(transaction);
    return {
      ...transaction,
      _id: result.insertedId
    };
  }

  /**
   * Find transactions by user ID
   * @param {string} userId
   * @param {number} limit
   * @returns {Promise<Transaction[]>}
   */
  async findByUserId(userId, limit = 10) {
    return await this.collection
      .find({ user_id: userId })
      .sort({ timestamp: -1 })
      .limit(limit)
      .toArray();
  }

  /**
   * Get daily financial stats
   * @returns {Promise<Object|null>}
   */
  async getDailyStats() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const result = await this.collection.aggregate([
      { $match: { timestamp: { $gte: today } } },
      {
        $group: {
          _id: null,
          totalBets: { $sum: '$bet' },
          totalPayouts: { $sum: '$payout' },
          totalRevenue: { $sum: { $subtract: ['$bet', '$payout'] } },
          transactionCount: { $sum: 1 }
        }
      }
    ]).toArray();

    return result[0] || null;
  }
}

module.exports = { MongoTransactionRepository };
