const { createUser, DEFAULT_BALANCE } = require('../../domain/entities');

/**
 * MongoDB User Repository
 * Implements UserRepositoryPort
 */
class MongoUserRepository {
  /**
   * @param {Db} db - MongoDB database instance
   */
  constructor(db) {
    this.collection = db.collection('users');
  }

  /**
   * Find user by ID
   * @param {string} userId
   * @returns {Promise<User|null>}
   */
  async findById(userId) {
    return await this.collection.findOne({ _id: userId });
  }

  /**
   * Update user balance
   * @param {string} userId
   * @param {number} change - Amount to add (can be negative)
   * @returns {Promise<User>}
   */
  async updateBalance(userId, change) {
    const result = await this.collection.findOneAndUpdate(
      { _id: userId },
      {
        $inc: { balance: change },
        $set: { updatedAt: new Date() }
      },
      { returnDocument: 'after' }
    );

    return result.value || result;
  }

  /**
   * Create user with initial balance
   * @param {string} userId
   * @param {number} initialChange - Initial balance change from default
   * @returns {Promise<User>}
   */
  async createWithBalance(userId, initialChange = 0) {
    const user = createUser(userId, initialChange);
    await this.collection.insertOne(user);
    return user;
  }
}

module.exports = { MongoUserRepository };
