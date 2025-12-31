#!/bin/bash
# =============================================================================
# OpenEBS Installation Script
# =============================================================================
#
# Installs OpenEBS with automatic environment detection:
#   - Docker Talos (local dev): LocalPV Hostpath only (no Mayastor)
#   - Bare Metal / QEMU: Full Mayastor + LocalPV (replicated storage)
#
# Prerequisites:
#   - Kubernetes cluster running
#   - Helm 3.7+ installed
#   - For Mayastor: huge pages configured (vm.nr_hugepages=1024)
#
# Usage:
#   ./setup.sh              # Auto-detect environment
#   ./setup.sh --local      # Force LocalPV only (no Mayastor)
#   ./setup.sh --full       # Force full install with Mayastor
#
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
echo "  OpenEBS Installation"
echo "========================================"

# =============================================================================
# Environment Detection
# =============================================================================

detect_environment() {
    # Check for command line override
    if [ "$1" == "--local" ]; then
        echo "local"
        return
    fi
    if [ "$1" == "--full" ]; then
        echo "full"
        return
    fi

    # Check if running in Docker-based Talos (no huge pages support)
    # Docker containers can't allocate huge pages
    local node_info
    node_info=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}' 2>/dev/null || echo "")

    if echo "$node_info" | grep -qi "talos"; then
        # Check if huge pages are available (indicates bare metal / QEMU)
        local hugepages
        hugepages=$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.hugepages-2Mi}' 2>/dev/null || echo "0")

        if [ "$hugepages" != "0" ] && [ -n "$hugepages" ]; then
            echo "full"
        else
            echo "local"
        fi
    else
        # Non-Talos cluster - assume full support
        echo "full"
    fi
}

MODE=$(detect_environment "$1")
echo_info "Detected environment: $MODE"

# =============================================================================
# Prerequisites
# =============================================================================

if ! command -v helm &> /dev/null; then
    echo_error "Helm is not installed"
    exit 1
fi

# =============================================================================
# Add Helm Repository
# =============================================================================

echo_info "Adding OpenEBS Helm repository..."
helm repo add openebs https://openebs.github.io/openebs 2>/dev/null || true
helm repo update

# =============================================================================
# Create Namespace with Pod Security
# =============================================================================

echo_info "Creating openebs namespace..."
kubectl create namespace openebs --dry-run=client -o yaml | kubectl apply -f -

# OpenEBS requires privileged access
echo_info "Configuring Pod Security for openebs namespace..."
kubectl label namespace openebs \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite

# =============================================================================
# Install OpenEBS
# =============================================================================

if [ "$MODE" == "local" ]; then
    echo_info "Installing OpenEBS LocalPV Hostpath (no Mayastor)..."

    helm upgrade --install openebs openebs/openebs \
        --namespace openebs \
        --values "$SCRIPT_DIR/helm-values-localpv.yaml" \
        --wait \
        --timeout 5m

else
    echo_info "Installing OpenEBS with Mayastor (full)..."

    # Check huge pages
    HUGEPAGES=$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.hugepages-2Mi}' 2>/dev/null || echo "0")
    if [ "$HUGEPAGES" == "0" ] || [ -z "$HUGEPAGES" ]; then
        echo_warn "Huge pages not detected! Mayastor requires vm.nr_hugepages=1024"
        echo_warn "Falling back to LocalPV only..."

        helm upgrade --install openebs openebs/openebs \
            --namespace openebs \
            --values "$SCRIPT_DIR/helm-values-localpv.yaml" \
            --wait \
            --timeout 5m
    else
        echo_info "Huge pages detected: $HUGEPAGES"

        helm upgrade --install openebs openebs/openebs \
            --namespace openebs \
            --values "$SCRIPT_DIR/helm-values-full.yaml" \
            --wait \
            --timeout 10m
    fi
fi

# =============================================================================
# Wait for Pods
# =============================================================================

echo_info "Waiting for OpenEBS pods to be ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=openebs \
    -n openebs --timeout=300s 2>/dev/null || true

# =============================================================================
# Set Default StorageClass
# =============================================================================

echo_info "Setting OpenEBS as default StorageClass..."

# Remove default from other storage classes
kubectl get sc -o name 2>/dev/null | xargs -I {} kubectl patch {} \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true

# Set openebs-hostpath as default
kubectl patch storageclass openebs-hostpath \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "========================================"
echo_info "OpenEBS installation complete!"
echo "========================================"
echo ""
echo "Installed mode: $MODE"
echo ""
echo "Storage Classes:"
kubectl get sc 2>/dev/null || echo "  (initializing...)"
echo ""
echo "Pods:"
kubectl get pods -n openebs 2>/dev/null || echo "  (initializing...)"
echo ""

if [ "$MODE" == "full" ]; then
    echo "For Mayastor, create DiskPools after installation:"
    echo "  kubectl apply -f openebs-diskpool.yaml"
    echo ""
fi

echo "Usage:"
echo "  # Create PVC with default StorageClass (openebs-hostpath)"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: v1"
echo "  kind: PersistentVolumeClaim"
echo "  metadata:"
echo "    name: my-pvc"
echo "  spec:"
echo "    accessModes: [\"ReadWriteOnce\"]"
echo "    resources:"
echo "      requests:"
echo "        storage: 1Gi"
echo "  EOF"
echo ""
