#!/bin/bash
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
echo "  Build Local Docker Images"
echo "========================================"

# Use Minikube's Docker daemon
echo_info "Switching to Minikube's Docker daemon..."
eval $(minikube docker-env)

# Clone api-gateway repository if not exists
API_GW_DIR="/tmp/api-gateway"

if [ ! -d "$API_GW_DIR" ]; then
    echo_info "Cloning api-gateway repository..."
    git clone https://github.com/d7561985/api-gateway.git "$API_GW_DIR"
else
    echo_info "Updating api-gateway repository..."
    cd "$API_GW_DIR" && git pull
fi

cd "$API_GW_DIR/envoy"

# Build images
echo_info "Building api-gateway image..."
docker build -t api-gateway:local -f api-gateway/Dockerfile . || {
    echo_warn "api-gateway build failed, using placeholder"
    docker pull nginx:alpine
    docker tag nginx:alpine api-gateway:local
}

echo_info "Building auth-adapter image..."
docker build -t auth-adapter:local -f auth-adapter/Dockerfile . || {
    echo_warn "auth-adapter build failed, using placeholder"
    docker pull nginx:alpine
    docker tag nginx:alpine auth-adapter:local
}

# Build health-demo from tools directory
echo_info "Building health-demo image..."
if [ -d "$API_GW_DIR/tools/health-demo" ]; then
    docker build -t health-demo:local -f "$API_GW_DIR/tools/health-demo/Dockerfile" "$API_GW_DIR/tools/health-demo" || {
        echo_warn "health-demo build failed, using placeholder"
        docker pull nginx:alpine
        docker tag nginx:alpine health-demo:local
    }
else
    echo_warn "health-demo directory not found, using placeholder"
    docker pull nginx:alpine
    docker tag nginx:alpine health-demo:local
fi

# Verify images
echo ""
echo_info "Built images:"
docker images | grep -E "api-gateway|auth-adapter|health-demo" | head -10

echo ""
echo "========================================"
echo_info "Local images build complete!"
echo "========================================"
echo ""
echo "Images available in Minikube:"
echo "  - api-gateway:local"
echo "  - auth-adapter:local"
echo "  - health-demo:local"
echo ""
echo "Note: These images use pullPolicy: Never in k8app values"
echo ""
