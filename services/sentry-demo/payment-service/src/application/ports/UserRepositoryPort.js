/**
 * User Repository Port (Interface)
 * Infrastructure layer must implement this interface
 *
 * @interface UserRepositoryPort
 */

/**
 * @typedef {Object} UserRepositoryPort
 * @property {function(string): Promise<User|null>} findById - Find user by ID
 * @property {function(string, number): Promise<User>} updateBalance - Update user balance
 * @property {function(string, number): Promise<User>} createWithBalance - Create user with initial balance
 */

/**
 * Create a UserRepositoryPort interface validator
 * Ensures implementation has all required methods
 * @param {Object} implementation
 * @returns {UserRepositoryPort}
 */
function validateUserRepository(implementation) {
  const required = ['findById', 'updateBalance', 'createWithBalance'];

  for (const method of required) {
    if (typeof implementation[method] !== 'function') {
      throw new Error(`UserRepository must implement ${method}()`);
    }
  }

  return implementation;
}

module.exports = { validateUserRepository };
