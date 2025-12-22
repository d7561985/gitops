/**
 * Transaction Repository Port (Interface)
 *
 * @interface TransactionRepositoryPort
 */

/**
 * @typedef {Object} TransactionRepositoryPort
 * @property {function(Transaction): Promise<Transaction>} create - Create a new transaction
 * @property {function(string, number): Promise<Transaction[]>} findByUserId - Find transactions by user ID
 */

/**
 * Validate TransactionRepository implementation
 * @param {Object} implementation
 * @returns {TransactionRepositoryPort}
 */
function validateTransactionRepository(implementation) {
  const required = ['create'];

  for (const method of required) {
    if (typeof implementation[method] !== 'function') {
      throw new Error(`TransactionRepository must implement ${method}()`);
    }
  }

  return implementation;
}

module.exports = { validateTransactionRepository };
