package main

import (
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	grpcprometheus "github.com/grpc-ecosystem/go-grpc-prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	grpcx "github.com/tel-io/instrumentation/middleware/grpc"
	"github.com/tel-io/tel/v2"
	"golang.org/x/net/context"
	"google.golang.org/grpc"
	"google.golang.org/grpc/grpclog"

	envoy_service_auth_v3 "github.com/envoyproxy/go-control-plane/envoy/service/auth/v3"
)

func parseRCConf() *RCConf {
	rcConf := &RCConf{}

	rcConf.URL = os.Getenv("RECAPTCHA_URL")
	rcConf.SecretV2 = os.Getenv("RECAPTCHA_SECRET_V2")
	rcConf.SecretV3 = os.Getenv("RECAPTCHA_SECRET_V3")
	rcConf.MinScore = 0.5 //FIXME should be configurable?

	return rcConf
}

func main() {
	logg, closer := tel.New(context.Background(), tel.GetConfigFromEnv())
	defer closer()

	logg.Info("starting auth-adapter")

	sigs := make(chan os.Signal, 1)

	signal.Notify(sigs, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)

	// load auth config
	authCfg, err := LoadConfig("/opt/auth-adapter/config.yaml")
	if err != nil {
		panic(err)
	}

	grpcServer := grpc.NewServer(
		grpc.ChainUnaryInterceptor(
			grpcprometheus.UnaryServerInterceptor,
			grpcx.UnaryServerInterceptor(),
		),
		grpc.StreamInterceptor(grpcprometheus.StreamServerInterceptor),
	)

	// Start metrics server
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		logg.Info("Metrics server listening on :9090")
		if err := http.ListenAndServe(":9090", mux); err != nil {
			logg.Error("Metrics server error: " + err.Error())
		}
	}()

	go func() {
		listener, err := net.Listen("tcp", ":9000")
		if err != nil {
			grpclog.Fatalf("failed to listen: %v", err)
		}

		s, err := NewServer(&logg, os.Getenv("AUTH_SERVICE_ADDR"), authCfg, parseRCConf())
		if err != nil {
			panic(err)
		}

		envoy_service_auth_v3.RegisterAuthorizationServer(grpcServer, s)

		// Register gRPC metrics
		grpcprometheus.Register(grpcServer)

		logg.Info("gRPC service started at :9000")
		err = grpcServer.Serve(listener)
		if err != nil {
			panic(err)
		}
	}()

	<-sigs
	logg.Info("stopping...")
	grpcServer.Stop()

	logg.Info("done.")
}
