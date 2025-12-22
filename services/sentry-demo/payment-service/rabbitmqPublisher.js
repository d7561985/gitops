const amqp = require('amqplib');
const Sentry = require('@sentry/node');

class PaymentPublisher {
  constructor() {
    this.connection = null;
    this.channel = null;
    this.rabbitmqUrl = process.env.RABBITMQ_URL || 'amqp://admin:password@localhost:5672';
    this.isConnecting = false;
  }

  async connect() {
    if (this.isConnecting || (this.connection && this.channel)) {
      return;
    }

    this.isConnecting = true;
    
    try {
      this.connection = await amqp.connect(this.rabbitmqUrl);
      this.channel = await this.connection.createChannel();

      // Declare exchange and queue
      await this.channel.assertExchange('gaming', 'topic', { durable: true });
      await this.channel.assertQueue('analytics.payments', { durable: true });
      await this.channel.bindQueue('analytics.payments', 'gaming', 'payment.*');

      // Handle connection events
      this.connection.on('error', (err) => {
        console.error('RabbitMQ connection error:', err);
        Sentry.captureException(err);
        this.connection = null;
        this.channel = null;
      });

      this.connection.on('close', () => {
        console.log('RabbitMQ connection closed');
        this.connection = null;
        this.channel = null;
      });

      console.log('RabbitMQ connection established');
    } catch (error) {
      console.error('Failed to connect to RabbitMQ:', error);
      Sentry.captureException(error);
      this.connection = null;
      this.channel = null;
    } finally {
      this.isConnecting = false;
    }
  }

  async publishPaymentEvent(eventType, paymentData, traceHeaders) {
    const span = Sentry.startSpan({
      op: 'mq.publish',
      name: 'Publish payment event to RabbitMQ'
    });

    try {
      // Ensure connection
      if (!this.channel) {
        await this.connect();
      }

      if (!this.channel) {
        throw new Error('No RabbitMQ channel available');
      }

      // Prepare message with trace context
      const message = {
        type: eventType,
        data: paymentData,
        trace: traceHeaders,
        timestamp: Date.now()
      };

      // Publish with persistence
      await this.channel.publish(
        'gaming',
        `payment.${eventType}`,
        Buffer.from(JSON.stringify(message)),
        {
          persistent: true,
          headers: traceHeaders
        }
      );

      span.setData('mq.queue', 'analytics.payments');
      span.setData('mq.routing_key', `payment.${eventType}`);
      span.setData('mq.event_type', eventType);
      span.setTag('mq.published', 'true');

      console.log(`Published payment event: ${eventType} for user ${paymentData.userId}`);
    } catch (error) {
      console.error('Failed to publish payment event:', error);
      Sentry.captureException(error);
      span.setTag('mq.published', 'false');
      span.setTag('mq.error', error.message);
      
      // Reset connection for retry
      this.connection = null;
      this.channel = null;
    } finally {
      span.end();
    }
  }

  async close() {
    if (this.connection) {
      await this.connection.close();
      console.log('RabbitMQ connection closed');
    }
  }
}

// Singleton instance
let publisherInstance = null;

function getPublisher() {
  if (!publisherInstance) {
    publisherInstance = new PaymentPublisher();
  }
  return publisherInstance;
}

module.exports = { getPublisher };