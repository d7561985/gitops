#!/bin/bash
# =============================================================================
# Talos Cluster Setup Script (Layer 0)
# =============================================================================
# Usage: ./shared/scripts/setup-talos.sh [cluster-name] [patch-file]
#
# Environment variables (optional):
#   TALOS_CPUS_CP      - CPUs for control plane (default: 2)
#   TALOS_MEMORY_CP    - Memory in MB for control plane (default: 2048)
#   TALOS_CPUS_WORKER  - CPUs per worker (default: 5)
#   TALOS_MEMORY_WORKER - Memory in MB per worker (default: 4096)
#
# This script ONLY creates a Talos Kubernetes cluster:
#   1. Destroys existing cluster (if any)
#   2. Creates new Talos cluster with talosctl
#   3. Configures kubeconfig
#
# After cluster creation, run setup-infrastructure.sh for infrastructure.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# =============================================================================
# Configuration
# =============================================================================

CLUSTER_NAME="${1:-talos-local}"
PATCH_FILE="${2:-$ROOT_DIR/shared/talos/patches/docker.yaml}"
KUBECONFIG_PATH="$HOME/.kube/${CLUSTER_NAME}.yaml"

# Resource allocation
# Control plane: minimal (only K8s control plane components)
# Workers: more resources for actual workloads
CPUS_CP="${TALOS_CPUS_CP:-2}"
MEMORY_CP="${TALOS_MEMORY_CP:-2048}"
CPUS_WORKER="${TALOS_CPUS_WORKER:-5}"
MEMORY_WORKER="${TALOS_MEMORY_WORKER:-4096}"

echo "========================================"
echo "  Talos Cluster Setup (Layer 0)"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Cluster name:  $CLUSTER_NAME"
echo "  Patch file:    $PATCH_FILE"
echo "  Kubeconfig:    $KUBECONFIG_PATH"
echo "  Control plane: ${CPUS_CP} CPU, ${MEMORY_CP}MB RAM"
echo "  Workers (x2):  ${CPUS_WORKER} CPU, ${MEMORY_WORKER}MB RAM each"
echo ""

# =============================================================================
# Prerequisites Check
# =============================================================================

echo_header "Checking prerequisites"

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo_error "$1 is not installed"
        return 1
    fi
    echo_info "$1: $(command -v $1)"
}

check_command talosctl || exit 1
check_command kubectl || exit 1
check_command docker || exit 1

# Check Docker is running
if ! docker info &> /dev/null; then
    echo_error "Docker is not running. Please start Docker Desktop."
    exit 1
fi
echo_info "Docker is running"

# Check patch file exists
if [ ! -f "$PATCH_FILE" ]; then
    echo_error "Patch file not found: $PATCH_FILE"
    exit 1
fi
echo_info "Patch file exists: $PATCH_FILE"

# =============================================================================
# Clean up existing cluster
# =============================================================================

echo_header "Cleaning up existing cluster"

if talosctl cluster show --name "$CLUSTER_NAME" &>/dev/null 2>&1; then
    echo_warn "Found existing cluster: $CLUSTER_NAME"
    read -p "Delete and recreate? (y/N): " RECREATE
    if [[ ! "$RECREATE" =~ ^[Yy]$ ]]; then
        echo_info "Keeping existing cluster. Exiting."
        exit 0
    fi

    echo_info "Destroying existing cluster..."
    talosctl cluster destroy --name "$CLUSTER_NAME" || true
fi

# Clean up leftover files
rm -rf "$HOME/.talos/clusters/$CLUSTER_NAME" 2>/dev/null || true
rm -f "$KUBECONFIG_PATH" 2>/dev/null || true
echo_info "Cleanup complete"

# =============================================================================
# Create Talos Cluster
# =============================================================================

echo_header "Creating Talos cluster"

echo_info "Running talosctl cluster create..."
echo_info "This may take 2-5 minutes..."

talosctl cluster create \
    --name "$CLUSTER_NAME" \
    --provisioner docker \
    --controlplanes 1 \
    --workers 2 \
    --cpus "$CPUS_CP" \
    --memory "$MEMORY_CP" \
    --cpus-workers "$CPUS_WORKER" \
    --memory-workers "$MEMORY_WORKER" \
    --config-patch @"$PATCH_FILE" \
    --wait=false

# Wait for API server
echo_info "Waiting for Kubernetes API server..."
sleep 30

# Check talos is healthy
echo_info "Checking Talos health..."
talosctl --nodes 10.5.0.2 health --wait-timeout 3m || {
    echo_warn "Talos health check timed out (may be waiting for CNI)"
}

echo_info "Talos cluster created"

# =============================================================================
# Configure Kubeconfig
# =============================================================================

echo_header "Configuring kubeconfig"

# Get dynamic port from Docker
CONTAINER_NAME="${CLUSTER_NAME}-controlplane-1"
API_PORT=$(docker port "$CONTAINER_NAME" 6443 2>/dev/null | cut -d: -f2)

if [ -z "$API_PORT" ]; then
    echo_error "Could not get API port from Docker container: $CONTAINER_NAME"
    exit 1
fi

echo_info "API port: $API_PORT"

# Export kubeconfig
talosctl kubeconfig "$KUBECONFIG_PATH" --nodes 10.5.0.2

# Fix server URL (replace internal IP with localhost:dynamic_port)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|server: https://10.5.0.2:6443|server: https://127.0.0.1:$API_PORT|g" "$KUBECONFIG_PATH"
else
    sed -i "s|server: https://10.5.0.2:6443|server: https://127.0.0.1:$API_PORT|g" "$KUBECONFIG_PATH"
fi

echo_info "Kubeconfig saved: $KUBECONFIG_PATH"

# Test connection
export KUBECONFIG="$KUBECONFIG_PATH"
echo_info "Testing cluster connection..."
kubectl cluster-info || {
    echo_error "Could not connect to cluster"
    exit 1
}

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "========================================"
echo_info "Layer 0 complete - Talos cluster ready!"
echo "========================================"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Nodes:"
kubectl get nodes 2>/dev/null || echo "  (waiting for CNI to report Ready)"
echo ""
echo "Note: Nodes will show NotReady until CNI (Cilium) is installed."
echo ""
echo "Next steps:"
echo ""
echo "  1. Set kubeconfig:"
echo "     export KUBECONFIG=$KUBECONFIG_PATH"
echo ""
echo "  2. Run infrastructure setup (Layer 1-2-3):"
echo "     ./shared/scripts/setup-infrastructure.sh"
echo ""
echo "  3. Bootstrap ArgoCD (Layer 4):"
echo "     kubectl apply -f infra/poc/gitops-config/argocd/project.yaml"
echo "     kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml"
echo ""
