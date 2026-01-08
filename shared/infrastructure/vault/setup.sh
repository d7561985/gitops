#!/bin/bash
# =============================================================================
# Vault + VSO Installation Script
# =============================================================================
#
# STANDALONE MODE (persistent storage):
#   - Data persisted in PVC (data-vault-0)
#   - Requires init (first time) and unseal (every restart)
#   - Keys stored in: K8s secret "vault-keys" and file ".vault-keys"
#
# KNOWN ISSUES & SOLUTIONS:
#
# 1. CrashLoopBackOff after restart
#    Cause: Vault is sealed, liveness probe fails
#    Solution: Liveness probe configured with sealedcode=204 in helm-values.yaml
#              Run this script or unseal.sh to unseal
#
# 2. Lost unseal keys
#    Cause: Keys not saved during init
#    Solution: Keys are saved to K8s secret and .vault-keys file
#              If lost, delete PVC and reinitialize
#
# USAGE:
#   First install:  ./setup.sh
#   After restart:  ./setup.sh  (or ./unseal.sh for quick unseal)
#   Full reinstall: helm uninstall vault -n vault && kubectl delete pvc data-vault-0 -n vault && ./setup.sh
#
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VAULT_KEYS_FILE="$SCRIPT_DIR/.vault-keys"

# Load .env if exists
if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    source "$ROOT_DIR/.env"
    set +a
fi

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

# Wait for Vault pod to exist
echo_info "Waiting for Vault pod..."
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=120s 2>/dev/null || true

# Port forward in background
echo_info "Setting up port forwarding..."
kubectl port-forward svc/vault -n vault 8200:8200 &
PF_PID=$!
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'

# Check Vault status
echo_info "Checking Vault status..."

# vault status returns exit code 0 for unsealed, 1 for error, 2 for sealed
# We need to capture both output and exit code
set +e
VAULT_STATUS=$(vault status -format=json 2>&1)
VAULT_EXIT=$?
set -e

if [ $VAULT_EXIT -eq 1 ]; then
    # Connection error or other issue
    echo_error "Cannot connect to Vault, retrying..."
    sleep 5
    VAULT_STATUS=$(vault status -format=json 2>&1 || echo '{"initialized": false, "sealed": true}')
fi

# Parse status (handle both sealed and unsealed responses)
INITIALIZED=$(echo "$VAULT_STATUS" | jq -r '.initialized // false')
SEALED=$(echo "$VAULT_STATUS" | jq -r '.sealed // true')

echo_info "Vault initialized: $INITIALIZED, sealed: $SEALED"

# Initialize Vault if needed
if [ "$INITIALIZED" == "false" ]; then
    echo_info "Initializing Vault..."

    # Initialize with 1 key share and 1 threshold for simplicity (POC)
    # For production, use more shares: -key-shares=5 -key-threshold=3
    INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

    UNSEAL_KEY=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

    # Save keys to file (add to .gitignore!)
    echo_info "Saving Vault keys to $VAULT_KEYS_FILE"
    cat > "$VAULT_KEYS_FILE" << EOF
# Vault Unseal Keys - KEEP SECURE!
# Generated: $(date)
VAULT_UNSEAL_KEY=$UNSEAL_KEY
VAULT_ROOT_TOKEN=$ROOT_TOKEN
EOF
    chmod 600 "$VAULT_KEYS_FILE"

    # Also store in Kubernetes secret for convenience
    echo_info "Storing keys in Kubernetes secret..."
    kubectl create secret generic vault-keys -n vault \
        --from-literal=unseal-key="$UNSEAL_KEY" \
        --from-literal=root-token="$ROOT_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Unseal Vault
    echo_info "Unsealing Vault..."
    vault operator unseal "$UNSEAL_KEY"

    export VAULT_TOKEN="$ROOT_TOKEN"

    echo_info "Vault initialized and unsealed!"
    echo ""
    echo_warn "IMPORTANT: Save these credentials securely!"
    echo "  Unseal Key: $UNSEAL_KEY"
    echo "  Root Token: $ROOT_TOKEN"
    echo ""
    echo "  Keys saved to: $VAULT_KEYS_FILE"
    echo "  Keys also stored in: kubectl get secret vault-keys -n vault"
    echo ""

elif [ "$SEALED" == "true" ]; then
    echo_info "Vault is sealed, attempting to unseal..."

    # Try to get unseal key from Kubernetes secret
    UNSEAL_KEY=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.unseal-key}' 2>/dev/null | base64 -d || echo "")

    if [ -z "$UNSEAL_KEY" ] && [ -f "$VAULT_KEYS_FILE" ]; then
        source "$VAULT_KEYS_FILE"
        UNSEAL_KEY="$VAULT_UNSEAL_KEY"
    fi

    if [ -z "$UNSEAL_KEY" ]; then
        echo_error "Cannot find unseal key!"
        echo "  Check: kubectl get secret vault-keys -n vault"
        echo "  Or: $VAULT_KEYS_FILE"
        exit 1
    fi

    vault operator unseal "$UNSEAL_KEY"
    echo_info "Vault unsealed!"

    # Get root token
    ROOT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "")
    if [ -z "$ROOT_TOKEN" ] && [ -f "$VAULT_KEYS_FILE" ]; then
        source "$VAULT_KEYS_FILE"
        ROOT_TOKEN="$VAULT_ROOT_TOKEN"
    fi
    export VAULT_TOKEN="$ROOT_TOKEN"
else
    echo_info "Vault is already initialized and unsealed"

    # Get root token
    ROOT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "")
    if [ -z "$ROOT_TOKEN" ] && [ -f "$VAULT_KEYS_FILE" ]; then
        source "$VAULT_KEYS_FILE"
        ROOT_TOKEN="$VAULT_ROOT_TOKEN"
    fi

    if [ -z "$ROOT_TOKEN" ]; then
        echo_warn "Cannot find root token, some operations may fail"
        ROOT_TOKEN="root"  # Fallback for dev mode
    fi
    export VAULT_TOKEN="$ROOT_TOKEN"
fi

# Store root token in vault-admin-token secret for platform-core
echo_info "Creating vault-admin-token secret..."
kubectl create secret generic vault-admin-token -n vault \
    --from-literal=token="$VAULT_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

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

echo ""
echo "========================================"
echo_info "Vault + VSO installation complete!"
echo "========================================"
echo ""
echo "Vault Status:"
vault status
echo ""
echo "Next steps:"
echo "  1. Run platform-core to create policies and roles"
echo "  2. Access Vault UI: kubectl port-forward svc/vault -n vault 8200:8200"
echo "     Then open http://localhost:8200"
if [ -f "$VAULT_KEYS_FILE" ]; then
    echo "  3. Root token stored in: $VAULT_KEYS_FILE"
fi
echo ""
