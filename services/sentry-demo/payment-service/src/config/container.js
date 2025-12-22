const { ProcessPaymentUseCase, TrackFinancialMetricsUseCase } = require('../application/use-cases');
const {
  MongoUserRepository,
  MongoTransactionRepository,
  getPublisher,
  BusinessMetrics
} = require('../infrastructure');

/**
 * Dependency Injection Container
 * Creates and wires all dependencies
 *
 * @param {Db} db - MongoDB database instance
 * @returns {Object} Container with all use cases
 */
function createContainer(db) {
  // Infrastructure layer
  const userRepo = new MongoUserRepository(db);
  const transactionRepo = new MongoTransactionRepository(db);
  const messagePublisher = getPublisher();
  const metricsService = new BusinessMetrics();

  // Application layer - Use Cases
  const processPayment = new ProcessPaymentUseCase(
    userRepo,
    transactionRepo,
    messagePublisher
  );

  const trackMetrics = new TrackFinancialMetricsUseCase(
    metricsService,
    db
  );

  return {
    // Use Cases (used by both HTTP and Connect handlers)
    processPayment,
    trackMetrics,

    // Infrastructure (for health checks, etc.)
    userRepo,
    transactionRepo,
    messagePublisher,
    metricsService
  };
}

module.exports = { createContainer };
