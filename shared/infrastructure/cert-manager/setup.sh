#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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
echo "  cert-manager + CloudFlare DNS01"
echo "========================================"

# Check for CloudFlare API token
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ "$CLOUDFLARE_API_TOKEN" = "your-token-here" ]; then
    echo_warn "CLOUDFLARE_API_TOKEN not configured in .env"
    echo ""
    echo "To enable automatic TLS certificates:"
    echo ""
    echo "1. Create CloudFlare API Token:"
    echo "   https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    echo "2. Use template 'Edit zone DNS' or create custom token with:"
    echo "   - Zone / DNS / Edit"
    echo "   - Zone / Zone / Read"
    echo "   - Zone Resources: Include All Zones (or specific zone)"
    echo ""
    echo "3. Add token to .env:"
    echo "   CLOUDFLARE_API_TOKEN=your-actual-token"
    echo ""
    echo "Continuing without CloudFlare integration..."
    SKIP_CLOUDFLARE=true
else
    SKIP_CLOUDFLARE=false
    echo_info "CloudFlare API token found in configuration"
fi

# Add Jetstack Helm repo
echo_info "Adding Jetstack Helm repository..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Create namespace
echo_info "Creating cert-manager namespace..."
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Install cert-manager
echo_info "Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --wait \
  --timeout 5m \
  -f "$SCRIPT_DIR/helm-values.yaml"

# Wait for cert-manager to be ready
echo_info "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=120s

# Create CloudFlare secret and ClusterIssuer if token is provided
if [ "$SKIP_CLOUDFLARE" = false ]; then
    echo_header "Configuring CloudFlare DNS01"

    # Create CloudFlare API token secret
    echo_info "Creating CloudFlare API token secret..."
    kubectl create secret generic cloudflare-api-token \
        --namespace cert-manager \
        --from-literal=api-token="$CLOUDFLARE_API_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Apply ClusterIssuer (substitute environment variables)
    echo_info "Creating Let's Encrypt ClusterIssuers..."
    LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"
    export LETSENCRYPT_EMAIL
    envsubst < "$SCRIPT_DIR/cluster-issuers.yaml" | kubectl apply -f -

    echo_info "CloudFlare DNS01 configured!"
else
    echo_warn "Skipping CloudFlare configuration. Apply manually later:"
    echo "  1. Set CLOUDFLARE_API_TOKEN environment variable"
    echo "  2. Re-run this script, or manually apply:"
    echo "     kubectl create secret generic cloudflare-api-token \\"
    echo "       --namespace cert-manager \\"
    echo "       --from-literal=api-token=\$CLOUDFLARE_API_TOKEN"
    echo "     kubectl apply -f $SCRIPT_DIR/cluster-issuers.yaml"
fi

echo ""
echo "========================================"
echo_info "cert-manager installation complete!"
echo "========================================"
echo ""
echo "Useful commands:"
echo "  kubectl get clusterissuer           # List issuers"
echo "  kubectl get certificate -A          # List certificates"
echo "  kubectl describe certificate <name> # Check certificate status"
echo ""
