package main

import (
	"demo/pkg/health"
	"flag"
	"fmt"
	"log"
	"net"

	"google.golang.org/grpc"
	"google.golang.org/grpc/health/grpc_health_v1"
)

func main() {
	port := flag.Int("port", 8081, "grpc port")
	flag.Parse()

	startServer(port)
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
