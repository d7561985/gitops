#!/bin/bash
set -e

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

# Load .env file if exists
if [ -f "$ROOT_DIR/.env" ]; then
    echo_info "Loading configuration from .env..."
    set -a
    source "$ROOT_DIR/.env"
    set +a
fi

echo "========================================"
echo "  CloudFlare Tunnel (cloudflared)"
echo "========================================"
echo ""
echo "CloudFlare Tunnel allows exposing local services to the internet"
echo "without opening firewall ports or having a public IP."
echo ""

# Check for tunnel token
CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"

if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    echo_header "Setup Instructions"
    echo ""
    echo "To create a CloudFlare Tunnel:"
    echo ""
    echo "1. Go to CloudFlare Zero Trust Dashboard:"
    echo "   https://one.dash.cloudflare.com/"
    echo ""
    echo "2. Navigate to: Networks -> Tunnels -> Create a tunnel"
    echo ""
    echo "3. Choose 'Cloudflared' connector"
    echo ""
    echo "4. Name your tunnel (e.g., 'minikube-dev')"
    echo ""
    echo "5. Select 'Docker' as environment (we'll use the token)"
    echo ""
    echo "6. Copy the tunnel token (starts with 'eyJ...')"
    echo ""
    echo "7. Add to .env:"
    echo "   CLOUDFLARE_TUNNEL_TOKEN=eyJhIjo..."
    echo ""
    echo "8. Configure public hostname in CloudFlare dashboard:"
    echo "   - Public hostname: app.demo-poc-01.work"
    echo "   - Service: http://gateway.poc-dev.svc:80"
    echo "   (Cilium Gateway creates a service named 'gateway' in poc-dev namespace)"
    echo ""
    echo "9. Re-run this script"
    echo ""
    exit 0
fi

echo_info "CloudFlare Tunnel token found"

# Create namespace
NAMESPACE="${CLOUDFLARE_TUNNEL_NAMESPACE:-cloudflare}"
echo_info "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create secret with tunnel token
echo_info "Creating tunnel token secret..."
kubectl create secret generic cloudflare-tunnel-token \
    --namespace "$NAMESPACE" \
    --from-literal=token="$CLOUDFLARE_TUNNEL_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy cloudflared
echo_info "Deploying cloudflared..."
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"

# Wait for deployment
echo_info "Waiting for cloudflared to be ready..."
kubectl wait --for=condition=Available deployment/cloudflared \
    -n "$NAMESPACE" --timeout=120s || true

echo ""
echo "========================================"
echo_info "CloudFlare Tunnel deployed!"
echo "========================================"
echo ""
echo "Useful commands:"
echo "  kubectl logs -n $NAMESPACE -l app=cloudflared -f    # View logs"
echo "  kubectl get pods -n $NAMESPACE                      # Check status"
echo ""
echo "Configure routes in CloudFlare Dashboard:"
echo "  https://one.dash.cloudflare.com/ -> Networks -> Tunnels -> Your tunnel -> Public Hostname"
echo ""
echo "Add public hostname:"
echo "  Hostname: app.demo-poc-01.work"
echo "  Service:  HTTP://cilium-gateway-gateway.poc-dev.svc:80"
echo ""
echo "Note: Cilium creates a LoadBalancer service named 'cilium-gateway-{gateway-name}'"
echo "      Gateway name is 'gateway', namespace is 'poc-dev'"
echo ""
echo "The Gateway routes traffic based on path:"
echo "  /api/*  -> api-gateway (port 8080)"
echo "  /*      -> sentry-frontend (port 4200)"
echo ""
