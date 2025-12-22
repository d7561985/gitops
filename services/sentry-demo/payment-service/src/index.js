/**
 * Payment Service - Clean Architecture Entry Point
 *
 * Supports multiple protocols:
 * - HTTP REST (legacy, enabled by default)
 * - Connect RPC (modern, enabled by ENABLE_CONNECT=true)
 *
 * Both protocols use the SAME use cases!
 */

// IMPORTANT: Initialize Sentry BEFORE all other imports
const Sentry = require('./instrument');

const express = require('express');
const { MongoClient } = require('mongodb');
const promClient = require('prom-client');

// Clean Architecture imports
const { createContainer } = require('./config/container');
const { PaymentController, createHttpRoutes } = require('./presentation/http');

// Configuration
const PORT = process.env.PORT || 8083;
const ENABLE_REST = process.env.ENABLE_REST !== 'false';  // Default: true
const ENABLE_CONNECT = process.env.ENABLE_CONNECT === 'true';  // Default: false

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const app = express();
app.use(express.json());

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Connect to MongoDB and start server
async function main() {
  try {
    // Connect to MongoDB
    const mongoUrl = process.env.MONGODB_URL || 'mongodb://mongodb:27017/sentry-poc';
    const client = await MongoClient.connect(mongoUrl);
    const db = client.db('sentry_poc');
    console.log('Connected to MongoDB');

    // Create DI container
    const container = createContainer(db);

    // Protocol: Connect RPC (if enabled)
    if (ENABLE_CONNECT) {
      try {
        const { expressConnectMiddleware } = require('@connectrpc/connect-express');
        const { createConnectHandlers } = require('./presentation/connect');

        // Await async handler creation (loads ESM proto package)
        const routes = await createConnectHandlers(container.processPayment, container.trackMetrics);

        app.use(expressConnectMiddleware({ routes }));

        console.log('Connect RPC protocol enabled');
      } catch (error) {
        console.warn('Connect RPC not available:', error.message);
        console.warn('Install: npm install @connectrpc/connect @connectrpc/connect-express');
      }
    }

    // Protocol: HTTP REST (if enabled)
    if (ENABLE_REST) {
      const httpController = new PaymentController(
        container.processPayment,
        container.trackMetrics
      );
      createHttpRoutes(app, httpController);
      console.log('HTTP REST protocol enabled');
    }

    // Debug endpoints (always HTTP)
    setupDebugEndpoints(app);

    // Sentry error handler (must be after routes)
    Sentry.setupExpressErrorHandler(app);

    // Start server
    app.listen(PORT, () => {
      console.log(`Payment Service started on :${PORT}`);
      console.log(`Protocols: REST=${ENABLE_REST}, Connect=${ENABLE_CONNECT}`);
    });

  } catch (error) {
    console.error('Failed to start service:', error);
    process.exit(1);
  }
}

/**
 * Debug endpoints for error demonstration
 * These are always HTTP (not part of business logic)
 */
function setupDebugEndpoints(app) {
  app.get('/debug/crash', (req, res) => {
    Sentry.addBreadcrumb({
      message: 'User accessed debug crash endpoint',
      category: 'debug',
      level: 'info'
    });
    throw new Error('[DEMO] Payment Service crash triggered!');
  });

  app.get('/debug/memory-leak', (req, res) => {
    if (!global.memoryLeakArray) {
      global.memoryLeakArray = [];
    }
    const leakSize = 50 * 1024 * 1024;
    global.memoryLeakArray.push('X'.repeat(leakSize));

    res.json({
      status: 'Memory leak created',
      leakedItems: global.memoryLeakArray.length
    });
  });
}

main();
