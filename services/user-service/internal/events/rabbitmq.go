package events

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	ExchangeName = "gaming"
	ExchangeType = "topic"
)

// Event types
const (
	EventUserRegistered = "user.registered"
	EventUserLogin      = "user.login"
	EventUserLogout     = "user.logout"
)

// UserEvent represents a user-related event
type UserEvent struct {
	Type      string                 `json:"type"`
	UserID    string                 `json:"user_id"`
	Timestamp time.Time              `json:"timestamp"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// Publisher publishes events to RabbitMQ
type Publisher struct {
	conn    *amqp.Connection
	channel *amqp.Channel
}

// NewPublisher creates a new RabbitMQ publisher
func NewPublisher(uri string) (*Publisher, error) {
	conn, err := amqp.Dial(uri)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	channel, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open channel: %w", err)
	}

	// Declare exchange
	err = channel.ExchangeDeclare(
		ExchangeName,
		ExchangeType,
		true,  // durable
		false, // auto-deleted
		false, // internal
		false, // no-wait
		nil,   // arguments
	)
	if err != nil {
		channel.Close()
		conn.Close()
		return nil, fmt.Errorf("failed to declare exchange: %w", err)
	}

	return &Publisher{
		conn:    conn,
		channel: channel,
	}, nil
}

// Close closes the RabbitMQ connection
func (p *Publisher) Close() error {
	if p.channel != nil {
		p.channel.Close()
	}
	if p.conn != nil {
		return p.conn.Close()
	}
	return nil
}

// Publish publishes a user event
func (p *Publisher) Publish(ctx context.Context, event *UserEvent) error {
	event.Timestamp = time.Now()

	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	err = p.channel.PublishWithContext(ctx,
		ExchangeName,
		event.Type, // routing key
		false,      // mandatory
		false,      // immediate
		amqp.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqp.Persistent,
			Body:         body,
			Timestamp:    event.Timestamp,
		},
	)
	if err != nil {
		return fmt.Errorf("failed to publish event: %w", err)
	}

	return nil
}

// PublishUserRegistered publishes a user.registered event
func (p *Publisher) PublishUserRegistered(ctx context.Context, userID, email string) error {
	return p.Publish(ctx, &UserEvent{
		Type:   EventUserRegistered,
		UserID: userID,
		Metadata: map[string]interface{}{
			"email": email,
		},
	})
}

// PublishUserLogin publishes a user.login event
func (p *Publisher) PublishUserLogin(ctx context.Context, userID, sessionID string) error {
	return p.Publish(ctx, &UserEvent{
		Type:   EventUserLogin,
		UserID: userID,
		Metadata: map[string]interface{}{
			"session_id": sessionID,
		},
	})
}

// PublishUserLogout publishes a user.logout event
func (p *Publisher) PublishUserLogout(ctx context.Context, userID, sessionID string) error {
	return p.Publish(ctx, &UserEvent{
		Type:   EventUserLogout,
		UserID: userID,
		Metadata: map[string]interface{}{
			"session_id": sessionID,
		},
	})
}
