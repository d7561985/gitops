/**
 * Transaction Entity
 * @typedef {Object} Transaction
 * @property {string} id
 * @property {string} userId
 * @property {'WIN'|'LOSS'} type
 * @property {number} amount
 * @property {number} bet
 * @property {number} payout
 * @property {number} balanceAfter
 * @property {Date} timestamp
 */

/**
 * Create a new Transaction
 * @param {Object} params
 * @returns {Transaction}
 */
function createTransaction({ userId, bet, payout, balanceAfter }) {
  const netChange = payout - bet;
  return {
    userId,
    type: netChange >= 0 ? 'WIN' : 'LOSS',
    amount: Math.abs(netChange),
    bet,
    payout,
    balanceAfter,
    timestamp: new Date()
  };
}

module.exports = { createTransaction };
