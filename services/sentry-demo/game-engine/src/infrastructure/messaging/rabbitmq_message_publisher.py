"""RabbitMQ message publisher implementation"""
import os
import json
import logging
import pika
import sentry_sdk
from typing import Dict, Any, Optional
from threading import Lock

from src.application.ports.message_publisher_port import MessagePublisherPort

logger = logging.getLogger(__name__)


class RabbitMQMessagePublisher(MessagePublisherPort):
    """RabbitMQ implementation of message publisher"""

    def __init__(self, rabbitmq_url: str = None):
        self.rabbitmq_url = rabbitmq_url or os.environ.get(
            'RABBITMQ_URL', 'amqp://admin:password@localhost:5672'
        )
        self.connection: Optional[pika.BlockingConnection] = None
        self.channel: Optional[pika.channel.Channel] = None
        self.lock = Lock()
        self._connect()

    def _connect(self):
        """Establish connection to RabbitMQ"""
        try:
            params = pika.URLParameters(self.rabbitmq_url)
            self.connection = pika.BlockingConnection(params)
            self.channel = self.connection.channel()

            # Declare exchange and queue
            self.channel.exchange_declare(
                exchange='gaming',
                exchange_type='topic',
                durable=True
            )

            self.channel.queue_declare(
                queue='analytics.game_results',
                durable=True
            )

            self.channel.queue_bind(
                exchange='gaming',
                queue='analytics.game_results',
                routing_key='game.result'
            )

            logger.info("RabbitMQ connection established")

        except Exception as e:
            logger.error(f"Failed to connect to RabbitMQ: {e}")
            sentry_sdk.capture_exception(e)
            self.connection = None
            self.channel = None

    def publish_game_result(self, game_data: Dict[str, Any], trace_headers: Dict[str, str]) -> None:
        """Publish game result to RabbitMQ with trace propagation"""
        with self.lock:
            try:
                # Ensure connection is alive
                if not self.connection or self.connection.is_closed:
                    self._connect()

                if not self.channel:
                    logger.error("No RabbitMQ channel available")
                    return

                # Prepare message with trace context
                message = {
                    'data': game_data,
                    'trace': trace_headers,
                    'timestamp': game_data.get('timestamp')
                }

                # Publish with persistence
                self.channel.basic_publish(
                    exchange='gaming',
                    routing_key='game.result',
                    body=json.dumps(message),
                    properties=pika.BasicProperties(
                        delivery_mode=2,  # Make message persistent
                        headers=trace_headers
                    )
                )

                logger.info(f"Published game result for user {game_data.get('user_id')}")

            except Exception as e:
                logger.error(f"Failed to publish game result: {e}")
                sentry_sdk.capture_exception(e)
                self.connection = None
                self.channel = None

    def close(self):
        """Close RabbitMQ connection"""
        if self.connection and not self.connection.is_closed:
            self.connection.close()
            logger.info("RabbitMQ connection closed")
