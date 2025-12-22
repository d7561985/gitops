package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"connectrpc.com/connect"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"gitlab.com/gitops-poc-dzha/user-service/internal/config"
	"gitlab.com/gitops-poc-dzha/user-service/internal/events"
	"gitlab.com/gitops-poc-dzha/user-service/internal/jwt"
	"gitlab.com/gitops-poc-dzha/user-service/internal/repository/mongodb"
	"gitlab.com/gitops-poc-dzha/user-service/internal/service"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	"gitlab.com/gitops-poc-dzha/api/gen/user-service/go/user/v1/userv1connect"
)

var (
	port        = flag.String("port", "8081", "HTTP server port")
	metricsPort = flag.String("metrics-port", "9090", "Metrics server port")
)

func main() {
	flag.Parse()

	// Load configuration
	cfg := config.Load()
	if *port != "" {
		cfg.Port = *port
	}
	if *metricsPort != "" {
		cfg.MetricsPort = *metricsPort
	}

	fmt.Printf("Starting user-service on port %s (metrics: %s)\n", cfg.Port, cfg.MetricsPort)

	// Context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Connect to MongoDB
	mongoClient, err := mongo.Connect(ctx, options.Client().ApplyURI(cfg.MongoURI))
	if err != nil {
		fmt.Printf("Failed to connect to MongoDB: %v\n", err)
		os.Exit(1)
	}
	defer mongoClient.Disconnect(ctx)

	// Ping MongoDB
	if err := mongoClient.Ping(ctx, nil); err != nil {
		fmt.Printf("Failed to ping MongoDB: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("Connected to MongoDB")

	db := mongoClient.Database(cfg.MongoDBName)

	// Create repositories
	userRepo := mongodb.NewUserRepository(db)
	refreshTokenRepo := mongodb.NewRefreshTokenRepository(db)

	// Ensure indexes
	if err := userRepo.EnsureIndexes(ctx); err != nil {
		fmt.Printf("Failed to create user indexes: %v\n", err)
	}
	if err := refreshTokenRepo.EnsureIndexes(ctx); err != nil {
		fmt.Printf("Failed to create refresh token indexes: %v\n", err)
	}

	// Connect to RabbitMQ (optional - continue if fails)
	var eventPublisher *events.Publisher
	if cfg.RabbitMQURI != "" {
		eventPublisher, err = events.NewPublisher(cfg.RabbitMQURI)
		if err != nil {
			fmt.Printf("Warning: Failed to connect to RabbitMQ: %v (events disabled)\n", err)
		} else {
			defer eventPublisher.Close()
			fmt.Println("Connected to RabbitMQ")
		}
	}

	// Create JWT manager
	jwtManager := jwt.NewManager(cfg.JWTSecret, cfg.AccessTokenTTL)

	// Create services
	userService := service.NewUserService(userRepo, refreshTokenRepo, jwtManager, eventPublisher, cfg)
	authService := service.NewAuthService(jwtManager)

	// Create Connect interceptors for logging
	interceptors := connect.WithInterceptors(NewLoggingInterceptor())

	// Create HTTP mux for Connect handlers
	mux := http.NewServeMux()

	// Register UserService handler
	// Connect handler supports: Connect, gRPC, and gRPC-Web protocols automatically
	userPath, userHandler := userv1connect.NewUserServiceHandler(
		NewUserServiceServer(userService),
		interceptors,
	)
	mux.Handle(userPath, userHandler)

	// Register AuthSessionService handler
	authPath, authHandler := userv1connect.NewAuthSessionServiceHandler(
		NewAuthSessionServiceServer(authService),
		interceptors,
	)
	mux.Handle(authPath, authHandler)

	// Health check endpoint
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Create HTTP server with h2c (HTTP/2 without TLS)
	// This allows gRPC clients to connect without TLS
	server := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: h2c.NewHandler(mux, &http2.Server{}),
	}

	// Start metrics server on separate port
	go func() {
		metricsMux := http.NewServeMux()
		metricsMux.Handle("/metrics", promhttp.Handler())
		metricsMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("OK"))
		})
		fmt.Printf("Metrics server listening on :%s\n", cfg.MetricsPort)
		if err := http.ListenAndServe(":"+cfg.MetricsPort, metricsMux); err != nil {
			fmt.Printf("Metrics server error: %v\n", err)
		}
	}()

	// Start main server
	go func() {
		fmt.Printf("Connect server listening on :%s\n", cfg.Port)
		fmt.Println("Supported protocols: Connect, gRPC, gRPC-Web")
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fmt.Printf("Server error: %v\n", err)
		}
	}()

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	fmt.Println("Shutting down...")

	// Graceful shutdown with timeout
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		fmt.Printf("Shutdown error: %v\n", err)
	}

	fmt.Println("Server stopped")
}
