const Sentry = require('@sentry/node');
const { createProcessPaymentRequest, createTrackMetricsRequest } = require('../../application/dto');

/**
 * HTTP REST Controller for Payment Service
 */
class PaymentController {
  /**
   * @param {ProcessPaymentUseCase} processPayment
   * @param {TrackFinancialMetricsUseCase} trackMetrics
   */
  constructor(processPayment, trackMetrics) {
    this.processPayment = processPayment;
    this.trackMetrics = trackMetrics;
  }

  /**
   * Process payment endpoint
   * POST /process
   */
  async process(req, res) {
    const sentryTraceHeader = req.get('sentry-trace');
    const baggageHeader = req.get('baggage');

    const handler = async () => {
      try {
        const request = createProcessPaymentRequest({
          userId: req.body.userId,
          bet: req.body.bet,
          payout: req.body.payout
        });

        const result = await this.processPayment.execute(request);

        res.json(result);
      } catch (error) {
        Sentry.captureException(error);
        res.status(error.message.includes('required') ? 400 : 500)
           .json({ error: error.message });
      }
    };

    if (sentryTraceHeader) {
      await Sentry.continueTrace(
        { sentryTrace: sentryTraceHeader, baggage: baggageHeader },
        handler
      );
    } else {
      await handler();
    }
  }

  /**
   * Track financial metrics endpoint
   * POST /financial-metrics
   */
  async financialMetrics(req, res) {
    try {
      const request = createTrackMetricsRequest({
        scenario: req.body.scenario
      });

      const result = await this.trackMetrics.execute(request);

      res.json(result);
    } catch (error) {
      Sentry.captureException(error);
      res.status(500).json({ error: error.message });
    }
  }
}

module.exports = { PaymentController };
