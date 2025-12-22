const amqp = require('amqplib');
const Sentry = require('@sentry/node');

/**
 * RabbitMQ Message Publisher
 * Implements MessagePublisherPort
 */
class RabbitMQPublisher {
  constructor() {
    this.connection = null;
    this.channel = null;
    this.exchange = 'analytics';
    this.connecting = false;
  }

  /**
   * Initialize connection to RabbitMQ
   */
  async connect() {
    if (this.channel || this.connecting) return;

    this.connecting = true;
    try {
      const url = process.env.RABBITMQ_URL || 'amqp://guest:guest@rabbitmq:5672';
      this.connection = await amqp.connect(url);
      this.channel = await this.connection.createChannel();
      await this.channel.assertExchange(this.exchange, 'topic', { durable: true });

      this.connection.on('close', () => {
        console.log('RabbitMQ connection closed');
        this.channel = null;
        this.connection = null;
      });

      console.log('Connected to RabbitMQ');
    } catch (error) {
      console.error('Failed to connect to RabbitMQ:', error.message);
    } finally {
      this.connecting = false;
    }
  }

  /**
   * Publish payment event
   * @param {PaymentEvent} event
   * @param {Object} traceHeaders
   */
  async publishPaymentEvent(event, traceHeaders = {}) {
    await Sentry.startSpan(
      {
        name: 'Publish payment event',
        op: 'mq.publish',
        attributes: {
          'messaging.system': 'rabbitmq',
          'messaging.destination': 'payment.processed'
        }
      },
      async () => {
        if (!this.channel) {
          await this.connect();
        }

        if (!this.channel) {
          throw new Error('RabbitMQ not connected');
        }

        const message = {
          ...event,
          trace: traceHeaders
        };

        this.channel.publish(
          this.exchange,
          'payment.processed',
          Buffer.from(JSON.stringify(message)),
          {
            persistent: true,
            contentType: 'application/json',
            headers: traceHeaders
          }
        );
      }
    );
  }

  /**
   * Close connection
   */
  async close() {
    if (this.channel) await this.channel.close();
    if (this.connection) await this.connection.close();
  }
}

// Singleton instance
let instance = null;

function getPublisher() {
  if (!instance) {
    instance = new RabbitMQPublisher();
  }
  return instance;
}

module.exports = { RabbitMQPublisher, getPublisher };
