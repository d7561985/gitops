#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Cleanup function
PF_PID=""
cleanup() {
    if [ -n "$PF_PID" ]; then
        kill $PF_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  Vault + VSO Installation"
echo "========================================"

# Check vault CLI
if ! command -v vault &> /dev/null; then
    echo_error "vault CLI is not installed"
    echo "Install: brew install vault"
    exit 1
fi

# Add HashiCorp Helm repo
echo_info "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault
echo_info "Installing Vault..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install vault hashicorp/vault \
  --namespace vault \
  --wait \
  --timeout 5m \
  -f "$SCRIPT_DIR/helm-values.yaml"

# Wait for Vault to be ready
echo_info "Waiting for Vault to be ready..."
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=120s

# Install Vault Secrets Operator
echo_info "Installing Vault Secrets Operator..."
kubectl create namespace vault-secrets-operator-system --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator-system \
  --wait \
  --timeout 5m \
  -f "$SCRIPT_DIR/vso-values.yaml"

echo_info "Waiting for VSO to be ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=vault-secrets-operator \
  -n vault-secrets-operator-system --timeout=120s

# Configure Vault
echo_info "Configuring Vault..."

# Port forward in background
kubectl port-forward svc/vault -n vault 8200:8200 &
PF_PID=$!
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Enable KV v2
echo_info "Enabling KV v2 secrets engine..."
vault secrets enable -path=secret kv-v2 2>/dev/null || echo_warn "KV v2 already enabled"

# Enable Kubernetes auth
echo_info "Enabling Kubernetes auth..."
vault auth enable kubernetes 2>/dev/null || echo_warn "Kubernetes auth already enabled"

# Configure Kubernetes auth
echo_info "Configuring Kubernetes auth..."
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

# Cleanup handled by trap

echo ""
echo "========================================"
echo_info "Vault + VSO installation complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/setup-vault-secrets.sh to create secrets"
echo "  2. Access Vault UI: kubectl port-forward svc/vault -n vault 8200:8200"
echo "     Then open http://localhost:8200 (token: root)"
echo ""
