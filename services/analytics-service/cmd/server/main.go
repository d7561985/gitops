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
	"github.com/redis/go-redis/v9"
	"gitlab.com/gitops-poc-dzha/analytics-service/internal/service"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	analyticsv1connect "gitlab.com/gitops-poc-dzha/api/gen/analytics-service/go/analytics/v1/analyticsv1connect"
)

var (
	port        = flag.String("port", "8081", "HTTP server port")
	metricsPort = flag.String("metrics-port", "9090", "Metrics server port")
	redisAddr   = flag.String("redis-addr", "", "Redis address (optional, uses in-memory if not set)")
)

func main() {
	flag.Parse()

	// Override from environment
	if envPort := os.Getenv("PORT"); envPort != "" {
		*port = envPort
	}
	if envMetrics := os.Getenv("METRICS_PORT"); envMetrics != "" {
		*metricsPort = envMetrics
	}
	if envRedis := os.Getenv("REDIS_ADDR"); envRedis != "" {
		*redisAddr = envRedis
	}

	fmt.Printf("Starting analytics-service on port %s (metrics: %s)\n", *port, *metricsPort)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Setup Redis client (optional)
	var rdb *redis.Client
	if *redisAddr != "" {
		rdb = redis.NewClient(&redis.Options{
			Addr: *redisAddr,
		})
		if err := rdb.Ping(ctx).Err(); err != nil {
			fmt.Printf("Warning: Failed to connect to Redis: %v (using in-memory storage)\n", err)
			rdb = nil
		} else {
			fmt.Printf("Connected to Redis at %s\n", *redisAddr)
			defer rdb.Close()
		}
	} else {
		fmt.Println("Redis not configured, using in-memory storage")
	}

	// Create analytics service
	analyticsService := service.NewAnalyticsService(rdb)

	// Create Connect handler with logging interceptor
	interceptors := connect.WithInterceptors(NewLoggingInterceptor())
	analyticsServer := NewAnalyticsServiceServer(analyticsService)
	path, handler := analyticsv1connect.NewAnalyticsServiceHandler(analyticsServer, interceptors)

	// Create HTTP mux
	mux := http.NewServeMux()
	mux.Handle(path, handler)

	// Health check
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Create HTTP server with h2c (HTTP/2 without TLS)
	server := &http.Server{
		Addr:    ":" + *port,
		Handler: h2c.NewHandler(mux, &http2.Server{}),
	}

	// Start metrics server
	go func() {
		metricsMux := http.NewServeMux()
		metricsMux.Handle("/metrics", promhttp.Handler())
		metricsMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("OK"))
		})
		fmt.Printf("Metrics server listening on :%s\n", *metricsPort)
		if err := http.ListenAndServe(":"+*metricsPort, metricsMux); err != nil {
			fmt.Printf("Metrics server error: %v\n", err)
		}
	}()

	// Start main server
	go func() {
		fmt.Printf("Connect server listening on :%s\n", *port)
		fmt.Printf("Connect path: %s\n", path)
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

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		fmt.Printf("Shutdown error: %v\n", err)
	}

	fmt.Println("Server stopped")
}
