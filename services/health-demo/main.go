package main

import (
	"demo/pkg/health"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health/grpc_health_v1"
)

var (
	grpcRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "health_demo_grpc_requests_total",
			Help: "Total gRPC requests",
		},
		[]string{"method", "status"},
	)
	grpcRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "health_demo_grpc_request_duration_seconds",
			Help:    "gRPC request latency",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method"},
	)
)

func init() {
	prometheus.MustRegister(grpcRequestsTotal)
	prometheus.MustRegister(grpcRequestDuration)
}

func main() {
	port := flag.Int("port", 8081, "grpc port")
	metricsPort := flag.Int("metrics-port", 9090, "prometheus metrics port")
	flag.Parse()

	// Start metrics server
	go startMetricsServer(*metricsPort)

	startServer(port)
}

func startMetricsServer(port int) {
	http.Handle("/metrics", promhttp.Handler())
	log.Printf("starting metrics server on :%d\n", port)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil); err != nil {
		log.Fatalf("failed to start metrics server: %v", err)
	}
}

func startServer(port *int) {
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	gs := grpc.NewServer()
	grpc_health_v1.RegisterHealthServer(gs, new(health.Check))
	log.Printf("starting grpc on :%d\n", *port)

	gs.Serve(lis)
}
