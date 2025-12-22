package config

import (
	"os"
	"time"
)

type Config struct {
	// Server
	Port        string
	MetricsPort string

	// MongoDB
	MongoURI    string
	MongoDBName string

	// RabbitMQ
	RabbitMQURI string

	// JWT
	JWTSecret          string
	AccessTokenTTL     time.Duration
	RefreshTokenTTL    time.Duration
	RefreshTokenLength int
}

func Load() *Config {
	return &Config{
		// Server
		Port:        getEnv("PORT", "8081"),
		MetricsPort: getEnv("METRICS_PORT", "9090"),

		// MongoDB
		MongoURI:    getEnv("MONGODB_URI", "mongodb://localhost:27017"),
		MongoDBName: getEnv("MONGODB_DATABASE", "users"),

		// RabbitMQ
		RabbitMQURI: getEnv("RABBITMQ_URI", "amqp://guest:guest@localhost:5672/"),

		// JWT
		JWTSecret:          getEnv("JWT_SECRET", "change-me-in-production"),
		AccessTokenTTL:     15 * time.Minute,
		RefreshTokenTTL:    7 * 24 * time.Hour, // 7 days
		RefreshTokenLength: 64,
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
