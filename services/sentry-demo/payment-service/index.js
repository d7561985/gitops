// IMPORTANT: Initialize Sentry BEFORE all other imports
const Sentry = require('./instrument');

const express = require('express');
const { MongoClient } = require('mongodb');
const { getPublisher } = require('./rabbitmqPublisher');
// Import business metrics
const { BusinessMetrics, MetricAnomalyDetector } = require('./metrics.js');
// Prometheus metrics
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 8083;
// Artificial error rate disabled - was causing random failures
// const ERROR_RATE = 0.1; // 10% error rate for demo

// =============================================================================
// Prometheus Metrics Setup
// =============================================================================
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestsTotal = new promClient.Counter({
  name: 'payment_service_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

const httpRequestDuration = new promClient.Histogram({
  name: 'payment_service_request_duration_seconds',
  help: 'HTTP request latency',
  labelNames: ['method', 'route'],
  buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0],
  registers: [register]
});

const paymentsTotal = new promClient.Counter({
  name: 'payment_service_payments_total',
  help: 'Total payments processed',
  labelNames: ['status', 'type'],
  registers: [register]
});

const paymentAmount = new promClient.Histogram({
  name: 'payment_service_amount',
  help: 'Payment amounts distribution',
  buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000],
  registers: [register]
});

// Connect to MongoDB
let db;
MongoClient.connect(process.env.MONGODB_URL || 'mongodb://mongodb:27017/sentry-poc', {
  useUnifiedTopology: true
}).then(client => {
  console.log('Connected to MongoDB');
  db = client.db('sentry_poc');
}).catch(err => {
  console.error('Failed to connect to MongoDB:', err);
  process.exit(1);
});

app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Process payment endpoint
app.post('/process', async (req, res) => {
  // Continue trace from upstream
  const sentryTraceHeader = req.get('sentry-trace');
  const baggageHeader = req.get('baggage');
  
  // Use continueTrace if we have headers, otherwise just execute
  const handler = async () => {
    try {
    const { userId, bet, payout } = req.body;

    // Simulate external payment provider API call (minimal delay for realism)
    const delay = await Sentry.startSpan(
      {
        name: 'External payment provider API',
        op: 'http.client',
        attributes: {
          'http.method': 'POST',
          'http.url': 'https://payment-provider.example.com/charge'
        }
      },
      async () => {
        // Minimal delay to simulate network latency (5-15ms)
        const apiDelay = 5 + Math.random() * 10;
        await new Promise(resolve => setTimeout(resolve, apiDelay));
        return apiDelay;
      }
    );

    // Update user balance in database
    const result = await Sentry.startSpan(
      {
        name: 'Update user balance',
        op: 'db.update',
        attributes: {
          'db.system': 'mongodb',
          'db.collection': 'users',
          'db.operation': 'findOneAndUpdate'
        }
      },
      async () => {
        const netChange = payout - bet;
        
        // First check if user exists
        const existingUser = await db.collection('users').findOne({ _id: userId });
        
        if (!existingUser) {
          // Create new user with starting balance
          const newUser = {
            _id: userId,
            username: 'demo_player',
            balance: 1000 + netChange, // Starting balance + net change
            created_at: new Date(),
            updated_at: new Date()
          };
          await db.collection('users').insertOne(newUser);
          return { value: newUser };
        } else {
          // Update existing user
          return await db.collection('users').findOneAndUpdate(
            { _id: userId },
            { 
              $inc: { balance: netChange },
              $set: { updated_at: new Date() }
            },
            { returnDocument: 'after' }
          );
        }
      }
    );

    if (!result.value) {
      throw new Error('User not found');
    }

    // Record transaction
    const transaction = await Sentry.startSpan(
      {
        name: 'Record transaction',
        op: 'db.insert',
        attributes: {
          'db.system': 'mongodb',
          'db.collection': 'transactions'
        }
      },
      async () => {
        const netChange = payout - bet;
        const transaction = {
          user_id: userId,
          type: netChange >= 0 ? 'WIN' : 'LOSS',
          amount: Math.abs(netChange),
          bet: bet,
          payout: payout,
          timestamp: new Date(),
          balance_after: result.value.balance
        };
        await db.collection('transactions').insertOne(transaction);
        return transaction;
      }
    );

    // Publish to RabbitMQ for analytics
    try {
      const publisher = getPublisher();
      const activeSpan = Sentry.getActiveSpan();
      const traceHeaders = {
        'sentry-trace': activeSpan ? Sentry.spanToTraceHeader(activeSpan) : '',
        'baggage': Sentry.getBaggage() || ''
      };
      
      const netChange = payout - bet;
      await publisher.publishPaymentEvent(
        netChange >= 0 ? 'credit' : 'debit',
        {
          userId,
          amount: Math.abs(netChange),
          bet,
          payout,
          balance_after: result.value.balance,
          timestamp: transaction.timestamp
        },
        traceHeaders
      );
    } catch (mqError) {
      // Don't fail the request if RabbitMQ is down
      console.error('Failed to publish to RabbitMQ:', mqError);
    }

    // Track business metrics
    await Sentry.startSpan(
      {
        name: 'Track financial metrics',
        op: 'metrics.track',
      },
      async () => {
        const netChange = payout - bet;
        const anomalyDetector = new MetricAnomalyDetector();
        
        // Track financial volumes
        if (netChange >= 0) {
          // Credit (winnings)
          BusinessMetrics.trackMetric(BusinessMetrics.DEPOSIT_AMOUNT, netChange, "currency");
          BusinessMetrics.trackMetric(BusinessMetrics.DEPOSIT_COUNT, 1, "none");
        } else {
          // Debit (losses)
          BusinessMetrics.trackMetric(BusinessMetrics.WITHDRAWAL_AMOUNT, Math.abs(netChange), "currency");
          BusinessMetrics.trackMetric(BusinessMetrics.WITHDRAWAL_COUNT, 1, "none");
        }
        
        // Track net revenue (house edge)
        const houseEdge = bet - payout;
        BusinessMetrics.trackMetric(BusinessMetrics.REVENUE_NET, houseEdge, "currency");
        
        // Track payment success rate (we're here, so it's successful)
        BusinessMetrics.trackMetric(BusinessMetrics.PAYMENT_SUCCESS_RATE, 100.0, "percent");
        
        // Calculate daily financial metrics
        const dailyStats = await getDailyFinancialStats(db);
        if (dailyStats) {
          // Check for revenue anomalies
          const revenueRate = (dailyStats.totalRevenue / dailyStats.totalBets) * 100;
          if (revenueRate < 0) {
            Sentry.captureMessage(
              `Negative revenue detected: ${revenueRate.toFixed(2)}%`,
              'warning'
            );
          }
        }
      }
    );
    
    // Set custom metrics (legacy)
    const netChange = payout - bet;
    Sentry.metrics.distribution('payment.amount', Math.abs(netChange));
    Sentry.metrics.distribution('payment.processing_time', delay);
    Sentry.getCurrentScope().setTag('payment.type', netChange >= 0 ? 'credit' : 'debit');

    res.json({
      success: true,
      newBalance: result.value.balance
    });

    } catch (error) {
      Sentry.captureException(error);
      res.status(500).json({ error: error.message });
    }
  };

  // Execute with or without trace context
  if (sentryTraceHeader) {
    await Sentry.continueTrace(
      { sentryTrace: sentryTraceHeader, baggage: baggageHeader },
      handler
    );
  } else {
    await handler();
  }
});

// Financial metrics demo endpoint
app.post('/financial-metrics', async (req, res) => {
  const handler = async () => {
    const transaction = BusinessMetrics.startBusinessTransaction('financial_metrics_demo');
    
    await Sentry.startTransaction(transaction, async () => {
      try {
        const { scenario } = req.body;
        const anomalyDetector = new MetricAnomalyDetector();
        
        if (scenario === 'payment_failure_spike') {
          // Simulate payment failures
          await Sentry.startSpan(
            {
              name: 'Simulate payment failures',
              op: 'demo.payment_failures',
            },
            async () => {
              // Track declining success rate
              anomalyDetector.trackWithAnomalyDetection(
                BusinessMetrics.PAYMENT_SUCCESS_RATE,
                85.0, // Below 95% threshold
                "percent",
                { scenario: "demo", alert: "critical" }
              );
              
              // Track multiple failed transactions
              for (let i = 0; i < 5; i++) {
                Sentry.captureException(new Error(`Payment provider error ${i + 1}`));
              }
            }
          );
          
          res.json({ status: "Payment failure spike triggered", success_rate: 85.0 });
          
        } else if (scenario === 'revenue_anomaly') {
          // Simulate revenue anomalies
          await Sentry.startSpan(
            {
              name: 'Simulate revenue anomaly',
              op: 'demo.revenue_anomaly',
            },
            async () => {
              // Negative revenue (paying out more than taking in)
              BusinessMetrics.trackMetric(BusinessMetrics.REVENUE_NET, -5000, "currency");
              
              // Unusual deposit/withdrawal ratio
              BusinessMetrics.trackMetric(BusinessMetrics.DEPOSIT_AMOUNT, 1000, "currency");
              BusinessMetrics.trackMetric(BusinessMetrics.WITHDRAWAL_AMOUNT, 6000, "currency");
              
              Sentry.captureMessage(
                "Revenue Alert: Negative daily revenue detected",
                'error'
              );
            }
          );
          
          res.json({ status: "Revenue anomaly triggered", net_revenue: -5000 });
          
        } else {
          // Normal financial metrics
          await Sentry.startSpan(
            {
              name: 'Normal financial metrics',
              op: 'demo.normal',
            },
            async () => {
              BusinessMetrics.trackMetric(BusinessMetrics.PAYMENT_SUCCESS_RATE, 98.5, "percent");
              BusinessMetrics.trackMetric(BusinessMetrics.REVENUE_NET, 2500, "currency");
              BusinessMetrics.trackMetric(BusinessMetrics.DEPOSIT_AMOUNT, 10000, "currency");
              BusinessMetrics.trackMetric(BusinessMetrics.WITHDRAWAL_AMOUNT, 7500, "currency");
            }
          );
          
          res.json({ status: "Normal financial metrics tracked" });
        }
      } catch (error) {
        Sentry.captureException(error);
        res.status(500).json({ error: error.message });
      }
    });
  };
  
  await handler();
});

// Helper function to get daily financial stats
async function getDailyFinancialStats(db) {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const result = await db.collection('transactions').aggregate([
      {
        $match: {
          timestamp: { $gte: today }
        }
      },
      {
        $group: {
          _id: null,
          totalBets: { $sum: '$bet' },
          totalPayouts: { $sum: '$payout' },
          totalRevenue: { $sum: { $subtract: ['$bet', '$payout'] } },
          transactionCount: { $sum: 1 }
        }
      }
    ]).toArray();
    
    return result[0] || null;
  } catch (error) {
    console.error('Error getting daily stats:', error);
    return null;
  }
}

// Debug endpoints for crash demonstrations
app.get('/debug/crash', (req, res) => {
  // Add breadcrumbs
  Sentry.addBreadcrumb({
    message: 'User accessed debug crash endpoint',
    category: 'debug',
    level: 'info',
    data: {
      endpoint: '/debug/crash',
      service: 'payment-service',
      userAgent: req.get('user-agent')
    }
  });
  
  // Set user context
  Sentry.setUser({
    id: 'debug-payment-user',
    username: 'payment_tester'
  });
  
  // Add runtime context
  const os = require('os');
  Sentry.setContext('runtime', {
    memory_mb: process.memoryUsage().rss / 1024 / 1024,
    heap_used_mb: process.memoryUsage().heapUsed / 1024 / 1024,
    cpu_count: os.cpus().length,
    node_version: process.version,
    uptime_seconds: process.uptime()
  });
  
  // Trigger crash
  throw new Error('[DEMO] Payment Service crash triggered! This demonstrates Node.js error tracking with rich context.');
});

app.get('/debug/promise-rejection', async (req, res) => {
  // Add breadcrumb
  Sentry.addBreadcrumb({
    message: 'Starting unhandled promise rejection demo',
    category: 'debug.promise',
    level: 'warning'
  });
  
  // Create a promise that will reject
  const problematicPromise = new Promise((resolve, reject) => {
    setTimeout(() => {
      reject(new Error('Unhandled promise rejection in payment processing'));
    }, 100);
  });
  
  // Intentionally don't catch it
  problematicPromise.then(() => {
    console.log('This will never run');
  });
  // Missing .catch() - this will trigger unhandledRejection
  
  res.json({ status: 'Promise rejection triggered - check Sentry' });
});

app.get('/debug/memory-leak', (req, res) => {
  // Static variable to persist between requests
  if (!global.memoryLeakArray) {
    global.memoryLeakArray = [];
  }
  
  // Add breadcrumb
  Sentry.addBreadcrumb({
    message: 'Creating memory leak',
    category: 'debug.memory',
    level: 'warning',
    data: {
      current_size: global.memoryLeakArray.length,
      memory_before_mb: process.memoryUsage().heapUsed / 1024 / 1024
    }
  });
  
  // Create 50MB of data
  const leakSize = 50 * 1024 * 1024;
  const bigString = 'X'.repeat(leakSize);
  global.memoryLeakArray.push(bigString);
  
  // Also create objects that reference each other (harder to GC)
  const circularRef = { data: new Array(1000000).fill('memory leak') };
  circularRef.self = circularRef;
  global.memoryLeakArray.push(circularRef);
  
  const memoryAfter = process.memoryUsage().heapUsed / 1024 / 1024;
  
  // Log memory growth
  Sentry.setContext('memory_leak', {
    heap_used_mb: memoryAfter,
    total_leaked_items: global.memoryLeakArray.length,
    estimated_leak_mb: global.memoryLeakArray.length * 50
  });
  
  // Capture warning
  Sentry.captureMessage(
    `Memory leak demo: ${memoryAfter.toFixed(2)}MB heap used, ${global.memoryLeakArray.length} items leaked`,
    'warning'
  );
  
  res.json({
    status: 'Memory leak created',
    heap_used_mb: memoryAfter,
    leaked_items: global.memoryLeakArray.length,
    estimated_total_leak_mb: global.memoryLeakArray.length * 50
  });
});

app.get('/debug/event-loop-block', (req, res) => {
  // Add breadcrumb
  Sentry.addBreadcrumb({
    message: 'Starting event loop blocking demo',
    category: 'debug.performance',
    level: 'error',
    data: { block_duration_ms: 3000 }
  });
  
  const start = Date.now();
  
  // Block the event loop for 3 seconds
  // This is BAD - demonstrates what NOT to do
  while (Date.now() - start < 3000) {
    // Intensive calculation
    Math.sqrt(Math.random());
  }
  
  // Log the blocking
  Sentry.captureMessage(
    'Event loop blocked for 3 seconds - this would freeze all requests!',
    'error'
  );
  
  res.json({
    status: 'Event loop was blocked',
    duration_ms: Date.now() - start,
    warning: 'This blocked ALL requests to this service for 3 seconds!'
  });
});

app.get('/debug/stack-overflow', (req, res) => {
  // Add breadcrumb
  Sentry.addBreadcrumb({
    message: 'Triggering stack overflow',
    category: 'debug.stack',
    level: 'error'
  });
  
  // Recursive function that will cause stack overflow
  let depth = 0;
  function recurse() {
    depth++;
    // Add some data to each frame to make it overflow faster
    const data = new Array(100).fill(`depth: ${depth}`);
    recurse(); // No base case - will overflow
  }
  
  try {
    recurse();
  } catch (error) {
    // Add context about the overflow
    Sentry.withScope(scope => {
      scope.setContext('stack_overflow', {
        max_depth_reached: depth,
        error_type: error.name,
        message: error.message
      });
      Sentry.captureException(error);
    });
    
    res.status(500).json({
      error: 'Stack overflow occurred',
      depth_reached: depth
    });
  }
});

app.get('/debug/type-error', (req, res) => {
  // Add breadcrumb
  Sentry.addBreadcrumb({
    message: 'Triggering type error',
    category: 'debug.type',
    level: 'error'
  });
  
  try {
    // Common Node.js type errors
    const data = { name: 'test' };
    
    // Try to call a non-function
    data.name(); // TypeError: data.name is not a function
    
  } catch (error) {
    Sentry.captureException(error);
    throw error; // Re-throw to trigger error handler
  }
});

app.get('/debug/async-error', async (req, res, next) => {
  // Add breadcrumb
  Sentry.addBreadcrumb({
    message: 'Triggering async error',
    category: 'debug.async',
    level: 'error'
  });
  
  // Async function that throws
  async function failingAsyncOperation() {
    await new Promise(resolve => setTimeout(resolve, 100));
    throw new Error('Async operation failed in payment service');
  }
  
  // Call without try/catch to demonstrate error handling
  await failingAsyncOperation();
  
  // This line won't be reached
  res.json({ status: 'ok' });
});

app.get('/debug/database-error', async (req, res) => {
  // Add breadcrumb
  Sentry.addBreadcrumb({
    message: 'Triggering database error',
    category: 'debug.database',
    level: 'error'
  });
  
  try {
    // Try to use an invalid MongoDB operation
    const result = await db.collection('payments').findOne({
      $invalidOperator: { field: 'value' } // This will fail
    });
  } catch (error) {
    // Add database context
    Sentry.withScope(scope => {
      scope.setContext('database_error', {
        operation: 'findOne',
        collection: 'payments',
        error_code: error.code,
        error_name: error.name
      });
      Sentry.captureException(error);
    });
    
    res.status(500).json({
      error: 'Database operation failed',
      details: error.message
    });
  }
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// IMPORTANT: setupExpressErrorHandler must be AFTER all routes but BEFORE other error handlers
Sentry.setupExpressErrorHandler(app);

// Start server
app.listen(PORT, () => {
  console.log(`Payment Service started on :${PORT}`);
});