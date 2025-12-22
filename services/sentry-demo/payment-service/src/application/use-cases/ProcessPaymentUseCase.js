const Sentry = require('@sentry/node');
const { createTransaction } = require('../../domain/entities');
const { createProcessPaymentResponse } = require('../dto');

/**
 * Process Payment Use Case
 * Handles payment processing, balance updates, and transaction recording
 */
class ProcessPaymentUseCase {
  /**
   * @param {UserRepositoryPort} userRepo
   * @param {TransactionRepositoryPort} transactionRepo
   * @param {MessagePublisherPort} messagePublisher
   */
  constructor(userRepo, transactionRepo, messagePublisher) {
    this.userRepo = userRepo;
    this.transactionRepo = transactionRepo;
    this.messagePublisher = messagePublisher;
  }

  /**
   * Execute the payment processing
   * @param {ProcessPaymentRequest} request
   * @returns {Promise<ProcessPaymentResponse>}
   */
  async execute(request) {
    const { userId, bet, payout } = request;
    const netChange = payout - bet;

    // Get or create user with balance update
    const user = await Sentry.startSpan(
      {
        name: 'Update user balance',
        op: 'db.update',
        attributes: { 'db.system': 'mongodb', 'db.collection': 'users' }
      },
      async () => {
        const existingUser = await this.userRepo.findById(userId);

        if (!existingUser) {
          return await this.userRepo.createWithBalance(userId, netChange);
        }

        return await this.userRepo.updateBalance(userId, netChange);
      }
    );

    // Record transaction
    const transaction = await Sentry.startSpan(
      {
        name: 'Record transaction',
        op: 'db.insert',
        attributes: { 'db.system': 'mongodb', 'db.collection': 'transactions' }
      },
      async () => {
        const txn = createTransaction({
          userId,
          bet,
          payout,
          balanceAfter: user.balance
        });

        return await this.transactionRepo.create(txn);
      }
    );

    // Publish event (fire-and-forget)
    this.publishPaymentEvent(userId, bet, payout, user.balance, transaction.timestamp);

    // Track metrics
    Sentry.metrics.distribution('payment.amount', Math.abs(netChange));
    Sentry.getCurrentScope().setTag('payment.type', netChange >= 0 ? 'credit' : 'debit');

    return createProcessPaymentResponse({
      success: true,
      newBalance: user.balance,
      transactionId: transaction._id?.toString() || transaction.id,
      transactionType: transaction.type
    });
  }

  /**
   * Publish payment event to message queue
   * @private
   */
  publishPaymentEvent(userId, bet, payout, balanceAfter, timestamp) {
    const netChange = payout - bet;
    const activeSpan = Sentry.getActiveSpan();

    const traceHeaders = {
      'sentry-trace': activeSpan ? Sentry.spanToTraceHeader(activeSpan) : '',
      'baggage': Sentry.getBaggage() || ''
    };

    this.messagePublisher.publishPaymentEvent(
      {
        type: netChange >= 0 ? 'credit' : 'debit',
        userId,
        amount: Math.abs(netChange),
        bet,
        payout,
        balanceAfter,
        timestamp
      },
      traceHeaders
    ).catch(err => console.error('Failed to publish payment event:', err));
  }
}

module.exports = { ProcessPaymentUseCase };
