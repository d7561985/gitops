const { validateUserRepository } = require('./UserRepositoryPort');
const { validateTransactionRepository } = require('./TransactionRepositoryPort');
const { validateMessagePublisher } = require('./MessagePublisherPort');

module.exports = {
  validateUserRepository,
  validateTransactionRepository,
  validateMessagePublisher
};
