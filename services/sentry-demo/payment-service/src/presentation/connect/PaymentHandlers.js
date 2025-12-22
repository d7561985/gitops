const { createProcessPaymentRequest, createTrackMetricsRequest } = require('../../application/dto');

/**
 * Load proto package and create Connect handlers
 *
 * Uses dynamic import() for ESM/CommonJS interop.
 * Must be awaited at startup before passing to expressConnectMiddleware.
 *
 * @param {ProcessPaymentUseCase} processPayment
 * @param {TrackFinancialMetricsUseCase} trackMetrics
 * @returns {Promise<function>} Router configuration function
 */
async function createConnectHandlers(processPayment, trackMetrics) {
  // Import PaymentService from generated ESM code at startup
  const { PaymentService } = await import('@gitops-poc-dzha/payment-service-nodejs/payment/v1/payment_pb.js');

  // Return sync function for expressConnectMiddleware
  return (router) => {
    router.service(PaymentService, {
      /**
       * Process payment via Connect protocol
       * Same business logic as HTTP /process endpoint
       */
      async process(req) {
        const request = createProcessPaymentRequest({
          userId: req.userId,
          bet: req.bet,
          payout: req.payout
        });

        const result = await processPayment.execute(request);

        // Return proto-compatible response
        return {
          success: result.success,
          newBalance: result.newBalance,
          transactionId: result.transactionId,
          transactionType: result.transactionType
        };
      },

      /**
       * Track financial metrics via Connect protocol
       * Same business logic as HTTP /financial-metrics endpoint
       */
      async trackFinancialMetrics(req) {
        const request = createTrackMetricsRequest({
          scenario: req.scenario
        });

        const result = await trackMetrics.execute(request);

        return {
          status: result.status,
          metrics: result.metrics
        };
      }
    });
  };
}

module.exports = { createConnectHandlers };
