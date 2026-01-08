#!/bin/bash
# =============================================================================
# kube-prometheus-stack Installation
# =============================================================================
# Installs Prometheus, Grafana, and Alertmanager with service discovery
# for all applications in the cluster.
#
# Features:
# - Prometheus Operator with CRDs
# - Grafana with pre-configured K8s dashboards
# - Alertmanager for alert routing
# - Auto-discovery of ServiceMonitors across all namespaces
# - Integration with Cilium/Hubble metrics
#
# Prerequisites:
# - Kubernetes cluster running
# - Helm 3.x installed
# - kubectl configured
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  kube-prometheus-stack Installation"
echo "========================================"

# Check prerequisites
if ! command -v helm &> /dev/null; then
    echo_error "Helm is not installed"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Add Helm repository
echo_info "Adding prometheus-community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace
echo_info "Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install kube-prometheus-stack
echo_info "Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --version 80.4.1 \
    --values "$SCRIPT_DIR/helm-values.yaml" \
    --wait \
    --timeout 10m

# Wait for pods to be ready
echo_info "Waiting for Prometheus pods..."
kubectl wait --for=condition=Ready pods \
    -l app.kubernetes.io/name=prometheus \
    -n monitoring \
    --timeout=300s || true

echo_info "Waiting for Grafana pods..."
kubectl wait --for=condition=Ready pods \
    -l app.kubernetes.io/name=grafana \
    -n monitoring \
    --timeout=300s || true

# Verify installation
echo ""
echo "========================================"
echo_info "Installation complete!"
echo "========================================"
echo ""
echo "Pods in monitoring namespace:"
kubectl get pods -n monitoring
echo ""

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret kube-prometheus-stack-grafana -n monitoring \
    -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "admin")

echo "Access information:"
echo ""
echo "Grafana:"
echo "  URL: http://localhost:3000 (after port-forward)"
echo "  Username: admin"
echo "  Password: $GRAFANA_PASSWORD"
echo ""
echo "Prometheus:"
echo "  URL: http://localhost:9090 (after port-forward)"
echo ""
echo "Quick access commands:"
echo "  kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "  kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090"
echo ""
echo "Or use Makefile shortcuts:"
echo "  make proxy-grafana     # Grafana UI"
echo "  make proxy-prometheus  # Prometheus UI"
echo "  make hubble-ui         # Hubble network flows"
echo ""
echo "========================================"
echo "  Dashboard Provisioning"
echo "========================================"
echo ""
echo "Dashboards are automatically loaded via ConfigMaps."
echo ""
echo "To download and install additional dashboards:"
echo "  cd $SCRIPT_DIR/dashboards"
echo "  ./download-dashboards.sh     # Download from grafana.com"
echo "  ./generate-configmaps.sh     # Generate ConfigMaps"
echo "  kubectl apply -k configmaps/ # Apply to cluster"
echo ""
echo "Dashboards by category:"
echo "  - Kubernetes: Node, Pod, Deployment (included by default)"
echo "  - Cilium/Hubble: Network flows, DNS, HTTP (ID: 13286, 13502, 13537, 13538)"
echo "  - Infrastructure: MongoDB, RabbitMQ, Redis"
echo ""
