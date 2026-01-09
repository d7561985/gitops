package main

import (
	"os"
	"strings"
	"testing"
)

func TestTLSWithSNIOverride(t *testing.T) {
	// Test scenario: connecting to IP-based ingress with custom Host header
	// This simulates connecting to another K8s cluster's ingress controller
	cfg := &APIConf{
		APIRoute: "/api/",
		Clusters: []ClusterConf{
			{
				Name: "remote_cluster_api",
				Addr: "10.0.0.50:443", // IP address of remote ingress
				Type: "http",
				TLS: &TLSConf{
					Enabled: true,
					SNI:     "api.remote-cluster.example.com", // Virtual host for ingress routing
				},
			},
			{
				Name: "local_service",
				Addr: "localhost:8080",
				Type: "http",
				// No TLS - backward compatibility
			},
		},
		APIsDescr: []struct {
			Name    string    `yaml:"name"`
			Cluster string    `yaml:"cluster"`
			Auth    *AuthConf `yaml:"auth"`
			Methods []struct {
				Name string    `yaml:"name"`
				Auth *AuthConf `yaml:"auth"`
			} `yaml:"methods"`
		}{
			{
				Name:    "RemoteService",
				Cluster: "remote_cluster_api",
				Methods: []struct {
					Name string    `yaml:"name"`
					Auth *AuthConf `yaml:"auth"`
				}{
					{Name: "GetData"},
				},
			},
			{
				Name:    "LocalService",
				Cluster: "local_service",
				Methods: []struct {
					Name string    `yaml:"name"`
					Auth *AuthConf `yaml:"auth"`
				}{
					{Name: "Process"},
				},
			},
		},
	}

	// Test IsTLS
	if !cfg.Clusters[0].IsTLS() {
		t.Error("Expected remote_cluster_api to have TLS enabled")
	}
	if cfg.Clusters[1].IsTLS() {
		t.Error("Expected local_service to NOT have TLS enabled")
	}

	// Test GetSNI with explicit override
	sni := cfg.Clusters[0].GetSNI()
	if sni != "api.remote-cluster.example.com" {
		t.Errorf("Expected SNI 'api.remote-cluster.example.com', got '%s'", sni)
	}

	// Test GetSNI auto-detection (falls back to IP when no SNI set)
	cfg.Clusters[0].TLS.SNI = ""
	sni = cfg.Clusters[0].GetSNI()
	if sni != "10.0.0.50" {
		t.Errorf("Expected auto-detected SNI '10.0.0.50', got '%s'", sni)
	}
	cfg.Clusters[0].TLS.SNI = "api.remote-cluster.example.com" // restore

	// Generate config
	outFile := "/tmp/envoy_tls_sni_test.yaml"
	defer os.Remove(outFile)

	err := GenerateEnvoyConfig(cfg, outFile)
	if err != nil {
		t.Fatalf("Failed to generate config: %v", err)
	}

	data, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("Failed to read generated config: %v", err)
	}
	content := string(data)

	// Verify TLS transport_socket is present
	if !strings.Contains(content, "transport_socket:") {
		t.Error("Expected transport_socket in generated config")
	}

	// Verify SNI is set correctly for TLS handshake
	if !strings.Contains(content, `sni: "api.remote-cluster.example.com"`) {
		t.Error("Expected SNI 'api.remote-cluster.example.com' in TLS config")
	}

	// Verify host_rewrite_literal is set for ingress routing
	if !strings.Contains(content, `host_rewrite_literal: "api.remote-cluster.example.com"`) {
		t.Error("Expected host_rewrite_literal for ingress routing")
	}

	// Verify local_service does NOT have TLS
	parts := strings.Split(content, "- name: local_service")
	if len(parts) < 2 {
		t.Fatal("Could not find local_service cluster")
	}
	localSection := parts[1]
	if idx := strings.Index(localSection, "- name:"); idx > 0 {
		localSection = localSection[:idx]
	}
	if strings.Contains(localSection, "transport_socket:") {
		t.Error("local_service should NOT have transport_socket")
	}

	// Verify LocalService routes do NOT have host_rewrite
	routeSection := strings.Split(content, "routes:")[1]
	routeSection = strings.Split(routeSection, "http_filters:")[0]

	localRouteSection := strings.Split(routeSection, "LocalService")[1]
	localRouteSection = strings.Split(localRouteSection, "- match")[0]
	if strings.Contains(localRouteSection, "host_rewrite_literal") {
		t.Error("LocalService routes should NOT have host_rewrite_literal")
	}
}

func TestTLSWithExampleCom(t *testing.T) {
	// Test with real example.com
	cfg := &APIConf{
		APIRoute: "/api/",
		Clusters: []ClusterConf{
			{
				Name: "example_com",
				Addr: "example.com:443",
				Type: "http",
				TLS: &TLSConf{
					Enabled: true,
					// SNI auto-detected from addr
				},
			},
		},
		APIsDescr: []struct {
			Name    string    `yaml:"name"`
			Cluster string    `yaml:"cluster"`
			Auth    *AuthConf `yaml:"auth"`
			Methods []struct {
				Name string    `yaml:"name"`
				Auth *AuthConf `yaml:"auth"`
			} `yaml:"methods"`
		}{
			{
				Name:    "Example",
				Cluster: "example_com",
				Methods: []struct {
					Name string    `yaml:"name"`
					Auth *AuthConf `yaml:"auth"`
				}{
					{Name: "Get"},
				},
			},
		},
	}

	// SNI should be auto-detected
	sni := cfg.Clusters[0].GetSNI()
	if sni != "example.com" {
		t.Errorf("Expected auto-detected SNI 'example.com', got '%s'", sni)
	}

	outFile := "/tmp/envoy_example_com_test.yaml"
	defer os.Remove(outFile)

	err := GenerateEnvoyConfig(cfg, outFile)
	if err != nil {
		t.Fatalf("Failed to generate config: %v", err)
	}

	data, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("Failed to read config: %v", err)
	}
	content := string(data)

	// Verify all TLS components
	if !strings.Contains(content, `sni: "example.com"`) {
		t.Error("Expected SNI 'example.com'")
	}
	if !strings.Contains(content, `host_rewrite_literal: "example.com"`) {
		t.Error("Expected host_rewrite_literal 'example.com'")
	}
	if !strings.Contains(content, `alpn_protocols: ["http/1.1"]`) {
		t.Error("Expected HTTP/1.1 ALPN for HTTP cluster")
	}
}

func TestGRPCWithTLS(t *testing.T) {
	cfg := &APIConf{
		APIRoute: "/api/",
		Clusters: []ClusterConf{
			{
				Name: "grpc_service",
				Addr: "grpc.example.com:443",
				Type: "grpc",
				TLS: &TLSConf{
					Enabled: true,
				},
			},
		},
		APIsDescr: []struct {
			Name    string    `yaml:"name"`
			Cluster string    `yaml:"cluster"`
			Auth    *AuthConf `yaml:"auth"`
			Methods []struct {
				Name string    `yaml:"name"`
				Auth *AuthConf `yaml:"auth"`
			} `yaml:"methods"`
		}{
			{
				Name:    "GrpcService",
				Cluster: "grpc_service",
				Methods: []struct {
					Name string    `yaml:"name"`
					Auth *AuthConf `yaml:"auth"`
				}{
					{Name: "Call"},
				},
			},
		},
	}

	outFile := "/tmp/envoy_grpc_tls_test.yaml"
	defer os.Remove(outFile)

	err := GenerateEnvoyConfig(cfg, outFile)
	if err != nil {
		t.Fatalf("Failed to generate config: %v", err)
	}

	data, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("Failed to read config: %v", err)
	}
	content := string(data)

	// gRPC should use h2 ALPN
	if !strings.Contains(content, `alpn_protocols: ["h2"]`) {
		t.Error("Expected h2 ALPN for gRPC cluster")
	}
	// Should have host_rewrite for gRPC too
	if !strings.Contains(content, `host_rewrite_literal: "grpc.example.com"`) {
		t.Error("Expected host_rewrite_literal for gRPC routes")
	}
}

func TestBackwardCompatibility(t *testing.T) {
	// Config without any TLS should work as before
	cfg := &APIConf{
		APIRoute: "/api/",
		Clusters: []ClusterConf{
			{
				Name: "old_service",
				Addr: "service.local:9090",
				Type: "grpc",
			},
		},
		APIsDescr: []struct {
			Name    string    `yaml:"name"`
			Cluster string    `yaml:"cluster"`
			Auth    *AuthConf `yaml:"auth"`
			Methods []struct {
				Name string    `yaml:"name"`
				Auth *AuthConf `yaml:"auth"`
			} `yaml:"methods"`
		}{
			{
				Name:    "OldService",
				Cluster: "old_service",
				Methods: []struct {
					Name string    `yaml:"name"`
					Auth *AuthConf `yaml:"auth"`
				}{
					{Name: "Method"},
				},
			},
		},
	}

	if cfg.Clusters[0].IsTLS() {
		t.Error("Cluster without TLS config should return false for IsTLS()")
	}

	outFile := "/tmp/envoy_backward_test.yaml"
	defer os.Remove(outFile)

	err := GenerateEnvoyConfig(cfg, outFile)
	if err != nil {
		t.Fatalf("Failed to generate config: %v", err)
	}

	data, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("Failed to read config: %v", err)
	}
	content := string(data)

	// Should NOT have transport_socket
	clusterSection := strings.Split(content, "- name: old_service")[1]
	if idx := strings.Index(clusterSection, "- name:"); idx > 0 {
		clusterSection = clusterSection[:idx]
	}
	if strings.Contains(clusterSection, "transport_socket:") {
		t.Error("Non-TLS cluster should NOT have transport_socket")
	}
	// Should NOT have host_rewrite
	if strings.Contains(content, "host_rewrite_literal") {
		t.Error("Non-TLS config should NOT have host_rewrite_literal")
	}
}
