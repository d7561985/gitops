package main

import (
	"os"
	"strings"
	"testing"
)

func TestUniversalTLSFix(t *testing.T) {
	testCases := []struct {
		name        string
		config      string
		checkRoutes []string
		description string
	}{
		{
			name: "API without methods (catch-all only)",
			config: `
api_route: /api/

clusters:
  - name: external
    addr: "api.external.com:443"
    type: "http"
    tls:
      enabled: true
      sni: "api.external.com"

apis:
  - name: service
    cluster: external
    auth: {policy: no-need}
`,
			checkRoutes: []string{"/api/service/"},
			description: "Should add headers to catch-all route",
		},
		{
			name: "API with specific methods",
			config: `
api_route: /api/

clusters:
  - name: external
    addr: "api.external.com:443"
    type: "http"
    tls:
      enabled: true
      sni: "api.external.com"

apis:
  - name: service
    cluster: external
    auth: {policy: no-need}
    methods:
      - name: ping
        auth: {policy: no-need}
      - name: health
        auth: {policy: no-need}
`,
			checkRoutes: []string{
				"/api/service/ping",
				"/api/service/health", 
				"/api/service/",
			},
			description: "Should add headers to all routes (methods + catch-all)",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Write config
			configFile := "test-" + strings.ReplaceAll(tc.name, " ", "-") + ".yaml"
			err := os.WriteFile(configFile, []byte(tc.config), 0644)
			if err != nil {
				t.Fatal("Failed to write config:", err)
			}
			defer os.Remove(configFile)

			// Generate Envoy config
			outputFile := "out-" + configFile
			cfg, err := LoadConfig(configFile)
			if err != nil {
				t.Fatal("Failed to load config:", err)
			}
			err = GenerateEnvoyConfig(cfg, outputFile)
			if err != nil {
				t.Fatal("Failed to generate config:", err)
			}
			defer os.Remove(outputFile)

			// Read and check
			content, err := os.ReadFile(outputFile)
			if err != nil {
				t.Fatal("Failed to read output:", err)
			}
			
			contentStr := string(content)

			// Check each route has the fix
			for _, route := range tc.checkRoutes {
				t.Run(route, func(t *testing.T) {
					// Find the route
					routeIdx := strings.Index(contentStr, `match: { prefix: "` + route)
					if routeIdx == -1 {
						t.Fatalf("Route %s not found", route)
					}

					// Get route section (next ~1000 chars should contain the route config)
					endIdx := routeIdx + 1500
					if endIdx > len(contentStr) {
						endIdx = len(contentStr)
					}
					routeSection := contentStr[routeIdx:endIdx]

					// Check for anti-redirect measures
					checks := map[string]string{
						"host_rewrite": `host_rewrite_literal: "api.external.com"`,
						"x-forwarded-proto": `key: "x-forwarded-proto"`,
						"https value": `value: "https"`,
						"overwrite action": `OVERWRITE_IF_EXISTS_OR_ADD`,
					}

					for checkName, checkStr := range checks {
						if !strings.Contains(routeSection, checkStr) {
							t.Errorf("Route %s missing %s: looking for %q", route, checkName, checkStr)
							// Print section for debugging
							t.Logf("Route section:\n%s", routeSection[:500])
						}
					}
				})
			}
		})
	}
}

func TestAllTLSRoutesGetHeaders(t *testing.T) {
	// Comprehensive test: any TLS cluster should trigger header addition
	config := `
api_route: /

clusters:
  - name: tls-cluster
    addr: "secure.example.com:443"
    type: "http"
    tls:
      enabled: true
      sni: "secure.example.com"
      
  - name: non-tls-cluster
    addr: "internal-service:8080"
    type: "http"

apis:
  - name: secure-api
    cluster: tls-cluster
    auth: {policy: no-need}
    methods:
      - name: test
        auth: {policy: no-need}
        
  - name: internal-api
    cluster: non-tls-cluster
    auth: {policy: no-need}
    methods:
      - name: test
        auth: {policy: no-need}
`

	configFile := "test-mixed-clusters.yaml"
	err := os.WriteFile(configFile, []byte(config), 0644)
	if err != nil {
		t.Fatal("Failed to write config:", err)
	}
	defer os.Remove(configFile)

	outputFile := "out-mixed.yaml"
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

	// Check TLS routes have headers
	tlsRouteIdx := strings.Index(contentStr, "/secure-api/test")
	if tlsRouteIdx == -1 {
		t.Fatal("TLS route not found")
	}
	tlsSection := contentStr[tlsRouteIdx:tlsRouteIdx+1000]
	
	if !strings.Contains(tlsSection, "x-forwarded-proto") {
		t.Error("TLS route should have x-forwarded-proto header")
	}
	if !strings.Contains(tlsSection, "host_rewrite_literal") {
		t.Error("TLS route should have host_rewrite_literal")
	}

	// Check non-TLS routes DON'T have unnecessary headers
	nonTlsRouteIdx := strings.Index(contentStr, "/internal-api/test")
	if nonTlsRouteIdx == -1 {
		t.Fatal("Non-TLS route not found")
	}
	nonTlsSection := contentStr[nonTlsRouteIdx:nonTlsRouteIdx+1000]
	
	if strings.Contains(nonTlsSection, "host_rewrite_literal") {
		t.Error("Non-TLS route should NOT have host_rewrite_literal")
	}
	if strings.Contains(nonTlsSection, "x-forwarded-proto") {
		t.Error("Non-TLS route should NOT have x-forwarded-proto header")
	}
}