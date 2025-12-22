/**
 * HTTP REST Routes
 * @param {Express} app
 * @param {PaymentController} controller
 */
function createHttpRoutes(app, controller) {
  // Health check
  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  // Payment processing
  app.post('/process', (req, res) => controller.process(req, res));

  // Financial metrics demo
  app.post('/financial-metrics', (req, res) => controller.financialMetrics(req, res));
}

module.exports = { createHttpRoutes };
