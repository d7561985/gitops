/**
 * User Entity
 * @typedef {Object} User
 * @property {string} id
 * @property {string} username
 * @property {number} balance
 * @property {Date} createdAt
 * @property {Date} updatedAt
 */

const DEFAULT_BALANCE = 1000;

/**
 * Create a new User with default balance
 * @param {string} userId
 * @param {number} initialBalanceChange
 * @returns {User}
 */
function createUser(userId, initialBalanceChange = 0) {
  return {
    _id: userId,
    username: 'demo_player',
    balance: DEFAULT_BALANCE + initialBalanceChange,
    createdAt: new Date(),
    updatedAt: new Date()
  };
}

module.exports = { createUser, DEFAULT_BALANCE };
