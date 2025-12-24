#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

echo "========================================"
echo "  GitOps POC Infrastructure Setup"
echo "  With Cilium CNI + Gateway API"
echo "========================================"

# ============================================
# Prerequisites Check
# ============================================

echo_header "Checking prerequisites"

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo_error "$1 is not installed"
        return 1
    fi
    echo_info "$1: $(command -v $1)"
}

check_command minikube || exit 1
check_command kubectl || exit 1
check_command helm || exit 1
check_command docker || exit 1

# Optional but recommended
check_command cilium || echo_warn "cilium CLI not installed (optional)"
check_command vault || echo_warn "vault CLI not installed (optional)"

# ============================================
# Minikube with Cilium CNI
# ============================================

echo_header "Setting up Minikube with Cilium"

MINIKUBE_RUNNING=false
if minikube status &> /dev/null; then
    MINIKUBE_RUNNING=true
    echo_warn "Minikube is already running."
    echo ""
    echo "For Cilium CNI, it's recommended to start fresh."
    echo "Current CNI:"
    kubectl get pods -n kube-system -l k8s-app=cilium &>/dev/null && echo "  Cilium detected" || echo "  NOT Cilium"
    echo ""
    read -p "Delete and recreate minikube? (y/N): " RECREATE
    if [[ "$RECREATE" =~ ^[Yy]$ ]]; then
        echo_info "Deleting existing minikube..."
        minikube delete
        MINIKUBE_RUNNING=false
    fi
fi

if [ "$MINIKUBE_RUNNING" = false ]; then
    echo_info "Starting Minikube with Cilium CNI..."
    minikube start \
        --cpus 4 \
        --memory 8192 \
        --disk-size 40g \
        --network-plugin=cni \
        --cni=false \
        --kubernetes-version=v1.30.0

    # Wait for API server
    echo_info "Waiting for Kubernetes API..."
    kubectl wait --for=condition=Ready node/minikube --timeout=120s
fi

# Enable metrics-server addon
echo_info "Enabling metrics-server addon..."
minikube addons enable metrics-server 2>/dev/null || true

# ============================================
# Install Gateway API CRDs (MUST be before Cilium)
# ============================================

echo_header "Installing Gateway API CRDs"
chmod +x "$ROOT_DIR/shared/infrastructure/gateway-api/setup.sh"
"$ROOT_DIR/shared/infrastructure/gateway-api/setup.sh"

# ============================================
# Install Cilium CNI with Gateway API
# ============================================

echo_header "Installing Cilium CNI"
chmod +x "$ROOT_DIR/shared/infrastructure/cilium/setup.sh"
"$ROOT_DIR/shared/infrastructure/cilium/setup.sh"

# Wait for networking to stabilize
echo_info "Waiting for cluster networking to stabilize..."
sleep 10

# ============================================
# Install cert-manager
# ============================================

echo_header "Installing cert-manager"
chmod +x "$ROOT_DIR/shared/infrastructure/cert-manager/setup.sh"
"$ROOT_DIR/shared/infrastructure/cert-manager/setup.sh"

# ============================================
# Install Vault + VSO
# ============================================

echo_header "Installing Vault + VSO"
chmod +x "$ROOT_DIR/shared/infrastructure/vault/setup.sh"
"$ROOT_DIR/shared/infrastructure/vault/setup.sh"

# ============================================
# Setup Registry Credentials in Vault
# ============================================
# Registry credentials are now managed via Vault + VSO.
# VaultStaticSecret in platform-core syncs to all namespaces automatically.

echo_header "Setting up Registry Credentials (Vault)"

# Check for credentials
if [ -z "$GITLAB_DEPLOY_TOKEN_USER" ] || [ -z "$GITLAB_DEPLOY_TOKEN" ]; then
    echo_warn "GITLAB_DEPLOY_TOKEN_USER and GITLAB_DEPLOY_TOKEN not set"
    echo ""
    echo "To create a Deploy Token:"
    echo "  1. Go to GitLab Group: Settings → Repository → Deploy tokens"
    echo "  2. Create token with 'read_registry' scope"
    echo "  3. Add to .env:"
    echo ""
    echo "     GITLAB_DEPLOY_TOKEN_USER='gitlab+deploy-token-xxxxx'"
    echo "     GITLAB_DEPLOY_TOKEN='gldt-xxxxxxxxxxxx'"
    echo ""
    echo_warn "Skipping registry credentials setup. Configure manually later."
    echo_info "See: docs/PREFLIGHT-CHECKLIST.md 'Этап 5: Registry Credentials в Vault'"
else
    REGISTRY="registry.gitlab.com"

    # Start port-forward
    kubectl port-forward svc/vault -n vault 8200:8200 &
    PF_PID=$!
    sleep 3

    export VAULT_ADDR='http://127.0.0.1:8200'

    # Get token
    if [ -f "$ROOT_DIR/shared/infrastructure/vault/.vault-keys" ]; then
        source "$ROOT_DIR/shared/infrastructure/vault/.vault-keys"
        export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
    else
        export VAULT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "root")
    fi

    # Create dockerconfigjson
    AUTH_STRING=$(echo -n "${GITLAB_DEPLOY_TOKEN_USER}:${GITLAB_DEPLOY_TOKEN}" | base64)
    DOCKER_CONFIG="{\"auths\":{\"${REGISTRY}\":{\"username\":\"${GITLAB_DEPLOY_TOKEN_USER}\",\"password\":\"${GITLAB_DEPLOY_TOKEN}\",\"auth\":\"${AUTH_STRING}\"}}}"

    # Store in Vault
    VAULT_PATH="${VAULT_PATH_PREFIX:-gitops-poc-dzha}/platform/registry"
    vault kv put secret/${VAULT_PATH} ".dockerconfigjson=${DOCKER_CONFIG}" 2>/dev/null && \
        echo_info "Registry credentials stored in Vault: secret/${VAULT_PATH}" || \
        echo_warn "Failed to store registry credentials. Configure manually later."

    # Cleanup
    kill $PF_PID 2>/dev/null || true
fi

# ============================================
# Install ArgoCD
# ============================================

echo_header "Installing ArgoCD"
chmod +x "$ROOT_DIR/shared/infrastructure/argocd/setup.sh"
"$ROOT_DIR/shared/infrastructure/argocd/setup.sh"

# ============================================
# Install Monitoring (Prometheus + Grafana)
# ============================================

echo_header "Installing Monitoring Stack"
chmod +x "$ROOT_DIR/shared/infrastructure/monitoring/setup.sh"
"$ROOT_DIR/shared/infrastructure/monitoring/setup.sh"

# ============================================
# Install External-DNS (optional, for domain mirrors)
# ============================================

if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
    echo_header "Installing External-DNS"
    chmod +x "$ROOT_DIR/shared/infrastructure/external-dns/setup.sh"
    "$ROOT_DIR/shared/infrastructure/external-dns/setup.sh"
else
    echo_header "Skipping External-DNS"
    echo_warn "CLOUDFLARE_API_TOKEN not set. External-DNS will not be installed."
    echo_info "To install later: CLOUDFLARE_API_TOKEN=xxx ./shared/infrastructure/external-dns/setup.sh"
fi

# ============================================
# Create Vault Admin Token Secret
# ============================================

echo_header "Creating Vault admin token secret"

# Get token from vault-keys secret (created by vault/setup.sh)
VAULT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "")

# Fallback to local file
if [ -z "$VAULT_TOKEN" ] && [ -f "$ROOT_DIR/shared/infrastructure/vault/.vault-keys" ]; then
    source "$ROOT_DIR/shared/infrastructure/vault/.vault-keys"
    VAULT_TOKEN="$VAULT_ROOT_TOKEN"
fi

# Fallback for dev mode (backward compatibility)
if [ -z "$VAULT_TOKEN" ]; then
    echo_warn "No vault-keys found, using 'root' token (dev mode only)"
    VAULT_TOKEN="root"
fi

kubectl create secret generic vault-admin-token \
    --namespace=vault \
    --from-literal=token="$VAULT_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
echo_info "Created vault-admin-token secret in vault namespace"

# ============================================
# Summary
# ============================================

echo ""
echo "========================================"
echo_info "Infrastructure setup complete!"
echo "========================================"
echo ""
echo "Installed components:"
echo "  - Cilium CNI with Gateway API (namespace: kube-system)"
echo "  - Gateway API CRDs v1.2.0"
echo "  - cert-manager (namespace: cert-manager)"
echo "  - Vault (namespace: vault)"
echo "  - Vault Secrets Operator (namespace: vault-secrets-operator-system)"
echo "  - Registry credentials in Vault (auto-synced to namespaces via VSO)"
echo "  - ArgoCD (namespace: argocd)"
echo "  - Prometheus + Grafana (namespace: monitoring)"
if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
echo "  - External-DNS (namespace: external-dns)"
fi
echo ""
echo "GatewayClass available:"
kubectl get gatewayclass 2>/dev/null || echo "  (none yet - Cilium may still be initializing)"
echo ""
echo "Next steps:"
echo ""
echo "1. Setup CloudFlare (если не сделано):"
echo "   export CLOUDFLARE_API_TOKEN=your-token"
echo "   ./shared/infrastructure/external-dns/setup.sh"
echo ""
echo "2. Migrate tunnel to locally-managed (для domain mirrors):"
echo "   ./shared/infrastructure/cloudflare-tunnel/migrate-to-locally-managed.sh"
echo ""
echo "3. Add GitLab repo credentials to ArgoCD:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   # Get password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "4. Apply bootstrap (starts everything automatically):"
echo "   kubectl apply -f infra/poc/gitops-config/argocd/project.yaml"
echo "   kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml"
echo ""
echo "5. Add domain mirrors (см. docs/domain-mirrors-guide.md):"
echo "   # Edit values.yaml:"
echo "   environments:"
echo "     dev:"
echo "       mirrors:"
echo "         - domain: mirror.example.com"
echo "           zoneId: abc123..."
echo ""
echo "6. Access Hubble UI (network observability):"
echo "   cilium hubble ui"
echo ""
echo "7. Access Grafana (metrics dashboards):"
echo "   kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "   # URL: http://localhost:3000 (admin / admin)"
echo ""
