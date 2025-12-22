#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if exists
if [ -f "$ROOT_DIR/.env" ]; then
    source "$ROOT_DIR/.env"
fi

# Set defaults from .env or use fallbacks
VAULT_PATH_PREFIX="${VAULT_PATH_PREFIX:-gitops-poc-dzha}"
SERVICES="${SERVICES:-api-gateway auth-adapter web-grpc web-http health-demo}"
ENVIRONMENTS="${ENVIRONMENTS:-dev staging prod}"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-poc}"

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
echo "  Vault Secrets Configuration"
echo "========================================"
echo ""
echo "Configuration:"
echo "  VAULT_PATH_PREFIX: $VAULT_PATH_PREFIX"
echo "  SERVICES:          $SERVICES"
echo "  ENVIRONMENTS:      $ENVIRONMENTS"
echo "  NAMESPACE_PREFIX:  $NAMESPACE_PREFIX"
echo ""

# Check vault CLI
if ! command -v vault &> /dev/null; then
    echo_error "vault CLI is not installed"
    echo "Install: brew install vault"
    exit 1
fi

# Port forward to Vault
echo_info "Starting port-forward to Vault..."
kubectl port-forward svc/vault -n vault 8200:8200 &
PF_PID=$!
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# Verify connection
echo_info "Verifying Vault connection..."
vault status

# Convert space-separated strings to arrays
read -ra SERVICES_ARR <<< "$SERVICES"
read -ra ENVIRONMENTS_ARR <<< "$ENVIRONMENTS"

# ============================================
# Create Policies
# ============================================

echo_info "Creating Vault policies..."

for SERVICE in "${SERVICES_ARR[@]}"; do
    for ENV in "${ENVIRONMENTS_ARR[@]}"; do
        POLICY_NAME="${VAULT_PATH_PREFIX}-${SERVICE}-${ENV}"

        echo_info "Creating policy: ${POLICY_NAME}"

        vault policy write ${POLICY_NAME} - <<EOF
# Policy for ${SERVICE} in ${ENV} environment
# Path: secret/data/${VAULT_PATH_PREFIX}/${SERVICE}/${ENV}/*

path "secret/data/${VAULT_PATH_PREFIX}/${SERVICE}/${ENV}/*" {
  capabilities = ["read"]
}

path "secret/metadata/${VAULT_PATH_PREFIX}/${SERVICE}/${ENV}/*" {
  capabilities = ["read", "list"]
}
EOF
    done
done

# ============================================
# Create Kubernetes Auth Roles
# ============================================

echo_info "Creating Kubernetes auth roles..."

for SERVICE in "${SERVICES_ARR[@]}"; do
    for ENV in "${ENVIRONMENTS_ARR[@]}"; do
        ROLE_NAME="${SERVICE}-${ENV}"
        # New namespace scheme: {prefix}-{env} instead of {service}-{env}
        if [ -n "$NAMESPACE_PREFIX" ]; then
            NAMESPACE="${NAMESPACE_PREFIX}-${ENV}"
        else
            NAMESPACE="${ENV}"
        fi
        POLICY_NAME="${VAULT_PATH_PREFIX}-${SERVICE}-${ENV}"

        echo_info "Creating role: ${ROLE_NAME} (namespace: ${NAMESPACE})"

        vault write auth/kubernetes/role/${ROLE_NAME} \
            bound_service_account_names=${SERVICE},default \
            bound_service_account_namespaces=${NAMESPACE} \
            policies=${POLICY_NAME} \
            ttl=1h
    done
done

# ============================================
# Create Sample Secrets
# ============================================

echo_info "Creating sample secrets..."

# API Gateway secrets
for ENV in "${ENVIRONMENTS_ARR[@]}"; do
    case $ENV in
        dev)
            LOG_LEVEL="debug"
            API_KEY="dev-api-key-12345678"
            ;;
        staging)
            LOG_LEVEL="info"
            API_KEY="staging-api-key-87654321"
            ;;
        prod)
            LOG_LEVEL="warn"
            API_KEY="prod-api-key-secure-production"
            ;;
    esac

    echo_info "Creating secret: api-gateway/${ENV}"
    vault kv put secret/${VAULT_PATH_PREFIX}/api-gateway/${ENV}/config \
        LOG_LEVEL="${LOG_LEVEL}" \
        API_KEY="${API_KEY}" \
        AUTH_ADAPTER_HOST="auth-adapter"
done

# Auth Adapter secrets
for ENV in "${ENVIRONMENTS_ARR[@]}"; do
    case $ENV in
        dev)
            VALID_TOKENS="dev-token-1,dev-token-2"
            JWT_SECRET="dev-jwt-secret-12345"
            ;;
        staging)
            VALID_TOKENS="staging-token-1,staging-token-2"
            JWT_SECRET="staging-jwt-secret-67890"
            ;;
        prod)
            VALID_TOKENS="prod-token-secure"
            JWT_SECRET="prod-jwt-secret-very-secure"
            ;;
    esac

    echo_info "Creating secret: auth-adapter/${ENV}"
    vault kv put secret/${VAULT_PATH_PREFIX}/auth-adapter/${ENV}/config \
        VALID_TOKENS="${VALID_TOKENS}" \
        JWT_SECRET="${JWT_SECRET}"
done

# Web services (minimal secrets for demo)
for SERVICE in "web-grpc" "web-http" "health-demo"; do
    for ENV in "${ENVIRONMENTS_ARR[@]}"; do
        echo_info "Creating secret: ${SERVICE}/${ENV}"
        vault kv put secret/${VAULT_PATH_PREFIX}/${SERVICE}/${ENV}/config \
            SERVICE_NAME="${SERVICE}" \
            ENVIRONMENT="${ENV}"
    done
done

# ============================================
# Verify Configuration
# ============================================

echo_info "Verifying secrets..."
echo ""
echo "Created secrets:"
vault kv list secret/${VAULT_PATH_PREFIX}/

echo ""
for SERVICE in "${SERVICES_ARR[@]}"; do
    echo "  ${SERVICE}:"
    vault kv list secret/${VAULT_PATH_PREFIX}/${SERVICE}/ 2>/dev/null || echo "    (no secrets)"
done

# Cleanup handled by trap

echo ""
echo "========================================"
echo_info "Vault secrets configuration complete!"
echo "========================================"
echo ""
echo "Secret path structure:"
echo "  secret/data/${VAULT_PATH_PREFIX}/{service}/{env}/config"
echo ""
echo "Example:"
echo "  secret/data/${VAULT_PATH_PREFIX}/api-gateway/dev/config"
echo ""
