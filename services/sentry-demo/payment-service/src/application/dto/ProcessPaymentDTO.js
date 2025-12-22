/**
 * Process Payment Request DTO
 * @typedef {Object} ProcessPaymentRequest
 * @property {string} userId
 * @property {number} bet
 * @property {number} payout
 */

/**
 * Process Payment Response DTO
 * @typedef {Object} ProcessPaymentResponse
 * @property {boolean} success
 * @property {number} newBalance
 * @property {string} transactionId
 * @property {'WIN'|'LOSS'} transactionType
 */

/**
 * Validate and create ProcessPaymentRequest
 * @param {Object} data
 * @returns {ProcessPaymentRequest}
 * @throws {Error} if validation fails
 */
function createProcessPaymentRequest(data) {
  const { userId, bet, payout } = data;

  if (!userId || typeof userId !== 'string') {
    throw new Error('userId is required');
  }
  if (typeof bet !== 'number' || bet < 0) {
    throw new Error('bet must be a non-negative number');
  }
  if (typeof payout !== 'number' || payout < 0) {
    throw new Error('payout must be a non-negative number');
  }

  return { userId, bet, payout };
}

/**
 * Create ProcessPaymentResponse
 * @param {Object} data
 * @returns {ProcessPaymentResponse}
 */
function createProcessPaymentResponse({ success, newBalance, transactionId, transactionType }) {
  return { success, newBalance, transactionId, transactionType };
}

module.exports = {
  createProcessPaymentRequest,
  createProcessPaymentResponse
};
