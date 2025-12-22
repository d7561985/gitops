#!/bin/bash
# =============================================================================
# Quick Vault Unseal Script
# =============================================================================
# Use this script to unseal Vault after pod restart
# For full setup/reinstall, use setup.sh instead
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_KEYS_FILE="$SCRIPT_DIR/.vault-keys"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if Vault pod is running
if ! kubectl get pod vault-0 -n vault &>/dev/null; then
    echo_error "Vault pod not found. Run setup.sh first."
    exit 1
fi

# Check Vault status
SEALED=$(kubectl exec vault-0 -n vault -- vault status -format=json 2>/dev/null | jq -r '.sealed // true')

if [ "$SEALED" == "false" ]; then
    echo_info "Vault is already unsealed"
    kubectl exec vault-0 -n vault -- vault status
    exit 0
fi

echo_info "Vault is sealed, attempting to unseal..."

# Try to get unseal key from Kubernetes secret first
UNSEAL_KEY=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.unseal-key}' 2>/dev/null | base64 -d || echo "")

# Fallback to local file
if [ -z "$UNSEAL_KEY" ] && [ -f "$VAULT_KEYS_FILE" ]; then
    echo_info "Loading keys from $VAULT_KEYS_FILE"
    source "$VAULT_KEYS_FILE"
    UNSEAL_KEY="$VAULT_UNSEAL_KEY"
fi

if [ -z "$UNSEAL_KEY" ]; then
    echo_error "Cannot find unseal key!"
    echo "  Check: kubectl get secret vault-keys -n vault"
    echo "  Or: $VAULT_KEYS_FILE"
    exit 1
fi

# Unseal
kubectl exec vault-0 -n vault -- vault operator unseal "$UNSEAL_KEY"

echo_info "Vault unsealed successfully!"
