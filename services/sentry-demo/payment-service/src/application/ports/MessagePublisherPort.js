/**
 * Message Publisher Port (Interface)
 *
 * @interface MessagePublisherPort
 */

/**
 * @typedef {Object} PaymentEvent
 * @property {'credit'|'debit'} type
 * @property {string} userId
 * @property {number} amount
 * @property {number} bet
 * @property {number} payout
 * @property {number} balanceAfter
 * @property {Date} timestamp
 */

/**
 * @typedef {Object} MessagePublisherPort
 * @property {function(PaymentEvent, Object): Promise<void>} publishPaymentEvent
 */

/**
 * Validate MessagePublisher implementation
 * @param {Object} implementation
 * @returns {MessagePublisherPort}
 */
function validateMessagePublisher(implementation) {
  if (typeof implementation.publishPaymentEvent !== 'function') {
    throw new Error('MessagePublisher must implement publishPaymentEvent()');
  }
  return implementation;
}

module.exports = { validateMessagePublisher };
