#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Gateway API version
GATEWAY_API_VERSION="v1.2.0"

echo "========================================"
echo "  Gateway API CRDs Installation"
echo "  Version: $GATEWAY_API_VERSION"
echo "========================================"

echo_info "Installing Gateway API CRDs..."

# Standard channel CRDs (GA resources)
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_gateways.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml"

# Experimental channel CRDs (optional - for TLSRoute, TCPRoute, etc.)
echo_info "Installing experimental Gateway API CRDs..."
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml" 2>/dev/null || echo_warn "TLSRoute CRD not available"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/experimental/gateway.networking.k8s.io_tcproutes.yaml" 2>/dev/null || echo_warn "TCPRoute CRD not available"

echo ""
echo "========================================"
echo_info "Gateway API CRDs installed!"
echo "========================================"
echo ""
echo "Installed CRDs:"
kubectl get crd | grep gateway.networking.k8s.io || true
echo ""
