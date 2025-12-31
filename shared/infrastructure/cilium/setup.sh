#!/bin/bash
# =============================================================================
# Cilium CNI Installation for Talos Linux
# =============================================================================
# Based on official documentation:
# - https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium
# - https://docs.cilium.io/en/stable/installation/k8s-install-helm/
#
# Prerequisites:
# - Talos cluster with CNI: none and proxy: disabled
# - Gateway API CRDs installed
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  Cilium CNI Installation"
echo "========================================"

# Check cilium CLI (optional but recommended)
if command -v cilium &> /dev/null; then
    echo_info "Cilium CLI found: $(cilium version --client 2>/dev/null || echo 'installed')"
else
    echo_warn "Cilium CLI not installed. Install for better debugging:"
    echo "  brew install cilium-cli"
fi

# Add Cilium Helm repo
echo_info "Adding Cilium Helm repository..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update

# Install Cilium
echo_info "Installing Cilium with Gateway API support..."
echo_info "Using bpf.hostLegacyRouting=true for Talos compatibility"

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --wait \
  --timeout 10m \
  -f "$SCRIPT_DIR/helm-values.yaml"

# Verify Cilium status
if command -v cilium &> /dev/null; then
    echo_info "Checking Cilium status..."
    cilium status --wait 2>/dev/null || cilium status 2>/dev/null || true
fi

# Verify GatewayClass was created
echo_info "Checking GatewayClass..."
kubectl get gatewayclass cilium -o wide 2>/dev/null || echo_warn "GatewayClass 'cilium' not found yet, may take a moment"

echo ""
echo "========================================"
echo_info "Cilium installation complete!"
echo "========================================"
echo ""
echo "Features enabled:"
echo "  - Gateway API support"
echo "  - L7 proxy (Envoy)"
echo "  - Hubble observability"
echo "  - kube-proxy replacement"
echo ""
echo "Useful commands:"
echo "  cilium status                    # Check Cilium status"
echo "  cilium connectivity test         # Run connectivity tests"
echo "  hubble observe                   # Watch network flows"
echo "  kubectl get gatewayclass         # Verify GatewayClass"
echo ""
