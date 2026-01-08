package main

import (
	"os"
	"strings"
	"testing"
)

func TestTLSProxyWithForwardedHeaders(t *testing.T) {
	// Test configuration with TLS proxy
	config := `
api_route: /api/

clusters:
  - name: external-api
    addr: "api.example.com:443"
    type: "http"
    tls:
      enabled: true
      sni: "api.example.com"

apis:
  - name: ExternalService
    cluster: external-api
    auth: {policy: no-need}
    methods:
      - name: status
        auth: {policy: no-need}
      - name: health
        auth: {policy: no-need}
`

	// Write test config
	configFile := "test-tls-proxy.yaml"
	err := os.WriteFile(configFile, []byte(config), 0644)
	if err != nil {
		t.Fatal("Failed to write config:", err)
	}
	defer os.Remove(configFile)

	// Generate Envoy config
	outputFile := "test-envoy-tls-proxy.yaml"
	cfg, err := LoadConfig(configFile)
	if err != nil {
		t.Fatal("Failed to load config:", err)
	}
	err = GenerateEnvoyConfig(cfg, outputFile)
	if err != nil {
		t.Fatal("Failed to generate config:", err)
	}
	defer os.Remove(outputFile)

	// Read generated config
	content, err := os.ReadFile(outputFile)
	if err != nil {
		t.Fatal("Failed to read output:", err)
	}

	contentStr := string(content)

	// Test 1: Check that TLS cluster has transport_socket
	if !strings.Contains(contentStr, `name: external-api`) {
		t.Error("Cluster 'external-api' not found")
	}
	if !strings.Contains(contentStr, `transport_socket:`) {
		t.Error("Missing transport_socket for TLS cluster")
	}
	if !strings.Contains(contentStr, `sni: "api.example.com"`) {
		t.Error("Missing SNI in TLS config")
	}

	// Test 2: Check that routes have host_rewrite_literal
	if !strings.Contains(contentStr, `host_rewrite_literal: "api.example.com"`) {
		t.Error("Missing host_rewrite_literal for TLS routes")
	}

	// Test 3: Check that x-forwarded-proto header is added for method routes
	statusRouteIdx := strings.Index(contentStr, "/api/ExternalService/status")
	if statusRouteIdx == -1 {
		t.Fatal("Status route not found")
	}
	
	// Get the route section for status endpoint
	statusSection := contentStr[statusRouteIdx:statusRouteIdx+1000]
	
	// Check for x-forwarded-proto header
	if !strings.Contains(statusSection, `x-forwarded-proto`) {
		t.Error("Missing x-forwarded-proto header for /status route")
	}
	if !strings.Contains(statusSection, `value: "https"`) {
		t.Error("x-forwarded-proto should be set to 'https'")
	}
	if !strings.Contains(statusSection, `OVERWRITE_IF_EXISTS_OR_ADD`) {
		t.Error("x-forwarded-proto should use OVERWRITE_IF_EXISTS_OR_ADD")
	}
	// Check x-forwarded-for uses correct enum
	if !strings.Contains(statusSection, `APPEND_IF_EXISTS_OR_ADD`) {
		t.Error("x-forwarded-for should use APPEND_IF_EXISTS_OR_ADD")
	}

	// Test 4: Check health route also has headers
	healthRouteIdx := strings.Index(contentStr, "/api/ExternalService/health")
	if healthRouteIdx == -1 {
		t.Fatal("Health route not found")
	}
	
	healthSection := contentStr[healthRouteIdx:healthRouteIdx+1000]
	
	if !strings.Contains(healthSection, `x-forwarded-proto`) {
		t.Error("Missing x-forwarded-proto header for /health route")
	}

	// Test 5: Check API-level catch-all route also has headers  
	catchAllIdx := strings.Index(contentStr, "/api/ExternalService/\"")
	if catchAllIdx == -1 {
		t.Fatal("Catch-all route not found")
	}
	
	catchAllSection := contentStr[catchAllIdx:catchAllIdx+1500]
	
	if !strings.Contains(catchAllSection, `x-forwarded-proto`) {
		t.Error("Missing x-forwarded-proto header for catch-all route")
	}
	if !strings.Contains(catchAllSection, `x-forwarded-for`) {
		t.Error("Missing x-forwarded-for header for catch-all route")  
	}
}

func TestTLSProxyRedirectPrevention(t *testing.T) {
	// This test validates that the configuration prevents redirects
	// by ensuring all necessary headers are set for TLS backends
	
	config := `
api_route: /

clusters:
  - name: backend
    addr: "backend.example.com:443"
    type: "http"
    tls:
      enabled: true
      sni: "backend.example.com"

apis:
  - name: service
    cluster: backend
    auth: {policy: no-need}
    methods:
      - name: ping
        auth: {policy: no-need}
`

	configFile := "test-redirect-prevention.yaml"
	err := os.WriteFile(configFile, []byte(config), 0644)
	if err != nil {
		t.Fatal("Failed to write config:", err)
	}
	defer os.Remove(configFile)

	outputFile := "test-envoy-redirect.yaml"
	cfg, err := LoadConfig(configFile)
	if err != nil {
		t.Fatal("Failed to load config:", err)
	}
	err = GenerateEnvoyConfig(cfg, outputFile)
	if err != nil {
		t.Fatal("Failed to generate config:", err)
	}
	defer os.Remove(outputFile)

	content, err := os.ReadFile(outputFile)
	if err != nil {
		t.Fatal("Failed to read output:", err)
	}

	contentStr := string(content)

	// Find the /service/ping route
	pingRouteIdx := strings.Index(contentStr, "/service/ping")
	if pingRouteIdx == -1 {
		t.Fatal("Ping route not found")
	}
	
	pingSection := contentStr[pingRouteIdx:pingRouteIdx+1200]
	
	// Verify all anti-redirect measures are in place:
	checks := []string{
		`host_rewrite_literal: "backend.example.com"`,  // Host header rewrite
		`x-forwarded-proto`,                             // Protocol header
		`value: "https"`,                                 // HTTPS value
		`prefix_rewrite: "/ping"`,                       // Path rewrite
	}
	
	for _, check := range checks {
		if !strings.Contains(pingSection, check) {
			t.Errorf("Route missing anti-redirect config: %s", check)
		}
	}
}