const Sentry = require('@sentry/node');
const { nodeProfilingIntegration } = require("@sentry/profiling-node");

// Get version from environment or use default
const version = process.env.APP_VERSION || '1.0.0';

// Initialize Sentry BEFORE any other imports
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  integrations: [
    nodeProfilingIntegration(),
  ],
  // Tracing - configurable via environment
  tracesSampleRate: parseFloat(process.env.SENTRY_TRACES_SAMPLE_RATE || '1.0'),
  // Set sampling rate for profiling
  profileSessionSampleRate: 1.0,
  profileLifecycle: 'trace',

  // Setting this option to true will send default PII data to Sentry
  sendDefaultPii: true,
  profileLifetime: 300,
  environment: process.env.SENTRY_ENVIRONMENT || 'development',
  debug: process.env.SENTRY_DEBUG === 'true',
  release: `payment-service@${version}`,
});

module.exports = Sentry;