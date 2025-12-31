#!/bin/bash
# =============================================================================
# Infrastructure Setup Script (Layer 1-2-3)
# =============================================================================
# Usage: ./shared/scripts/setup-infrastructure.sh
#
# Prerequisites:
#   - Kubernetes cluster (Talos, Minikube, cloud, etc.) already running
#   - kubectl configured with cluster access
#   - helm v3 installed
#   - .env file with required variables
#
# This script installs infrastructure on any Kubernetes cluster:
#   Layer 1: Gateway API CRDs, Cilium CNI
#   Layer 2: cert-manager, Vault + VSO
#   Layer 3: ArgoCD, Monitoring, External-DNS
#
# After this script, ArgoCD takes over for Layer 4 (applications).
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

echo "========================================"
echo "  Infrastructure Setup (Layer 1-2-3)"
echo "  Gateway API + Cilium + GitOps Stack"
echo "========================================"

# =============================================================================
# Load Configuration
# =============================================================================

if [ -f "$ROOT_DIR/.env" ]; then
    echo_info "Loading configuration from .env"
    set -a
    source "$ROOT_DIR/.env"
    set +a
else
    echo_warn ".env file not found at $ROOT_DIR/.env"
    echo_warn "Some features may not be configured (GitLab, Cloudflare, etc.)"
fi

# Set defaults
GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"
VAULT_PATH_PREFIX="${VAULT_PATH_PREFIX:-${GITLAB_GROUP:-gitops-poc}}"

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

check_command kubectl || exit 1
check_command helm || exit 1

# Optional tools
check_command cilium || echo_warn "cilium CLI not installed (optional)"
check_command vault || echo_warn "vault CLI not installed (optional)"

# Check cluster access
echo_info "Checking cluster access..."
kubectl cluster-info || { echo_error "Cannot connect to cluster. Set KUBECONFIG."; exit 1; }

# Show cluster info
echo ""
echo "Cluster nodes:"
kubectl get nodes -o wide 2>/dev/null || echo "  (nodes may show NotReady until CNI is installed)"
echo ""

# =============================================================================
# Layer 1: Network Foundation
# =============================================================================

# -----------------------------------------------------------------------------
# 1.1 Gateway API CRDs (MUST be before Cilium)
# -----------------------------------------------------------------------------

echo_header "Layer 1.1: Installing Gateway API CRDs"
chmod +x "$ROOT_DIR/shared/infrastructure/gateway-api/setup.sh"
"$ROOT_DIR/shared/infrastructure/gateway-api/setup.sh"

# -----------------------------------------------------------------------------
# 1.2 Prometheus CRDs (from prometheus-operator)
# -----------------------------------------------------------------------------
# Install CRDs early so Cilium can create ServiceMonitors.
# Download directly from prometheus-operator GitHub for reliability.

echo_header "Layer 1.2: Installing Prometheus CRDs"
echo_info "Installing Prometheus Operator CRDs (v0.79.0)..."

PROM_OP_VERSION="v0.79.0"
PROM_OP_CRD_URL="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${PROM_OP_VERSION}/example/prometheus-operator-crd"

# Install all required CRDs
for crd in servicemonitors podmonitors prometheusrules alertmanagerconfigs probes scrapeconfigs prometheuses alertmanagers thanosrulers; do
    kubectl apply --server-side -f "${PROM_OP_CRD_URL}/monitoring.coreos.com_${crd}.yaml" 2>/dev/null || true
done
echo_info "Prometheus CRDs installed"

# Verify ServiceMonitor CRD exists (required for Cilium)
kubectl get crd servicemonitors.monitoring.coreos.com &>/dev/null || {
    echo_error "ServiceMonitor CRD not installed!"
    exit 1
}

# Create monitoring namespace (required for Cilium dashboards ConfigMaps)
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------------------------------------------------------
# 1.3 Cilium CNI with Gateway API
# -----------------------------------------------------------------------------

echo_header "Layer 1.3: Installing Cilium CNI"
chmod +x "$ROOT_DIR/shared/infrastructure/cilium/setup.sh"
"$ROOT_DIR/shared/infrastructure/cilium/setup.sh"

# Wait for networking to stabilize
echo_info "Waiting for cluster networking to stabilize..."
sleep 10

# -----------------------------------------------------------------------------
# 1.4 OpenEBS Storage (replaces local-path-provisioner)
# -----------------------------------------------------------------------------

echo_header "Layer 1.4: Installing OpenEBS Storage"
chmod +x "$ROOT_DIR/shared/infrastructure/openebs/setup.sh"
"$ROOT_DIR/shared/infrastructure/openebs/setup.sh"

# =============================================================================
# Layer 2: Security & Secrets
# =============================================================================

# -----------------------------------------------------------------------------
# 2.1 cert-manager
# -----------------------------------------------------------------------------

echo_header "Layer 2.1: Installing cert-manager"
chmod +x "$ROOT_DIR/shared/infrastructure/cert-manager/setup.sh"
"$ROOT_DIR/shared/infrastructure/cert-manager/setup.sh"

# -----------------------------------------------------------------------------
# 2.2 Vault + VSO
# -----------------------------------------------------------------------------

echo_header "Layer 2.2: Installing Vault + VSO"
chmod +x "$ROOT_DIR/shared/infrastructure/vault/setup.sh"
"$ROOT_DIR/shared/infrastructure/vault/setup.sh"

# -----------------------------------------------------------------------------
# 2.3 Registry Credentials in Vault
# -----------------------------------------------------------------------------

echo_header "Layer 2.3: Setting up Registry Credentials (Vault)"

if [ -z "${GITLAB_DEPLOY_TOKEN_USER:-}" ] || [ -z "${GITLAB_DEPLOY_TOKEN:-}" ]; then
    echo_warn "GITLAB_DEPLOY_TOKEN_USER and GITLAB_DEPLOY_TOKEN not set"
    echo ""
    echo "To create a Deploy Token:"
    echo "  1. Go to GitLab Group: Settings -> Repository -> Deploy tokens"
    echo "  2. Create token with 'read_registry' scope"
    echo "  3. Add to .env:"
    echo ""
    echo "     GITLAB_DEPLOY_TOKEN_USER='gitlab+deploy-token-xxxxx'"
    echo "     GITLAB_DEPLOY_TOKEN='gldt-xxxxxxxxxxxx'"
    echo ""
    echo_warn "Skipping registry credentials. Configure manually later."
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
    VAULT_PATH="${VAULT_PATH_PREFIX}/platform/registry"
    vault kv put "secret/${VAULT_PATH}" ".dockerconfigjson=${DOCKER_CONFIG}" 2>/dev/null && \
        echo_info "Registry credentials stored in Vault: secret/${VAULT_PATH}" || \
        echo_warn "Failed to store registry credentials. Configure manually later."

    # Cleanup
    kill $PF_PID 2>/dev/null || true
fi

# =============================================================================
# Layer 3: GitOps & Observability
# =============================================================================

# -----------------------------------------------------------------------------
# 3.1 ArgoCD
# -----------------------------------------------------------------------------

echo_header "Layer 3.1: Installing ArgoCD"
chmod +x "$ROOT_DIR/shared/infrastructure/argocd/setup.sh"
"$ROOT_DIR/shared/infrastructure/argocd/setup.sh"

# -----------------------------------------------------------------------------
# 3.2 GitLab Repository Credentials for ArgoCD
# -----------------------------------------------------------------------------

echo_header "Layer 3.2: Configuring GitLab credentials for ArgoCD"

if [ -n "${GITLAB_TOKEN:-}" ] && [ -n "${GITLAB_GROUP:-}" ]; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: https://${GITLAB_HOST}/${GITLAB_GROUP}
  username: oauth2
  password: ${GITLAB_TOKEN}
EOF
    echo_info "GitLab credentials configured for https://${GITLAB_HOST}/${GITLAB_GROUP}"
else
    echo_warn "GITLAB_TOKEN or GITLAB_GROUP not set. Skipping GitLab credentials."
    echo_warn "ArgoCD won't be able to access private repositories."
fi

# -----------------------------------------------------------------------------
# 3.3 Monitoring (Prometheus + Grafana)
# -----------------------------------------------------------------------------

echo_header "Layer 3.3: Installing Monitoring Stack"
chmod +x "$ROOT_DIR/shared/infrastructure/monitoring/setup.sh"
"$ROOT_DIR/shared/infrastructure/monitoring/setup.sh"

# -----------------------------------------------------------------------------
# 3.4 External-DNS (optional)
# -----------------------------------------------------------------------------

if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo_header "Layer 3.4: Installing External-DNS"
    chmod +x "$ROOT_DIR/shared/infrastructure/external-dns/setup.sh"
    "$ROOT_DIR/shared/infrastructure/external-dns/setup.sh"
else
    echo_header "Layer 3.4: Skipping External-DNS"
    echo_warn "CLOUDFLARE_API_TOKEN not set. External-DNS will not be installed."
fi

# -----------------------------------------------------------------------------
# 3.5 Cloudflare Tunnel (optional)
# -----------------------------------------------------------------------------

echo_header "Layer 3.5: Configuring Cloudflare Tunnel credentials"

TUNNEL_ID="${CLOUDFLARE_TUNNEL_ID:-1172317a-8885-492f-9744-dfba842c4d88}"
TUNNEL_CREDS="$HOME/.cloudflared/${TUNNEL_ID}.json"

if [ -f "$TUNNEL_CREDS" ]; then
    kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic cloudflared-credentials \
        --namespace cloudflare \
        --from-file=credentials.json="$TUNNEL_CREDS" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo_info "Cloudflared credentials configured from $TUNNEL_CREDS"
else
    echo_warn "Tunnel credentials not found at $TUNNEL_CREDS"
    echo_warn "Run: ./shared/infrastructure/cloudflare-tunnel/setup.sh"
fi

# =============================================================================
# Final Setup: Vault Admin Token
# =============================================================================

echo_header "Creating Vault admin token secret"

VAULT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "")

if [ -z "$VAULT_TOKEN" ] && [ -f "$ROOT_DIR/shared/infrastructure/vault/.vault-keys" ]; then
    source "$ROOT_DIR/shared/infrastructure/vault/.vault-keys"
    VAULT_TOKEN="$VAULT_ROOT_TOKEN"
fi

if [ -z "$VAULT_TOKEN" ]; then
    echo_warn "No vault-keys found, using 'root' token (dev mode only)"
    VAULT_TOKEN="root"
fi

kubectl create secret generic vault-admin-token \
    --namespace=vault \
    --from-literal=token="$VAULT_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
echo_info "Created vault-admin-token secret in vault namespace"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "========================================"
echo_info "Infrastructure setup complete!"
echo "========================================"
echo ""
echo "Layer 1 (Network & Storage):"
echo "  - Gateway API CRDs v1.2.0"
echo "  - Prometheus CRDs (from kube-prometheus-stack)"
echo "  - Cilium CNI with Gateway API (namespace: kube-system)"
echo "  - OpenEBS Storage (namespace: openebs)"
echo ""
echo "Layer 2 (Security):"
echo "  - cert-manager (namespace: cert-manager)"
echo "  - Vault (namespace: vault)"
echo "  - Vault Secrets Operator (namespace: vault-secrets-operator-system)"
if [ -n "${GITLAB_DEPLOY_TOKEN_USER:-}" ]; then
echo "  - Registry credentials in Vault"
fi
echo ""
echo "Layer 3 (GitOps & Observability):"
echo "  - ArgoCD (namespace: argocd)"
if [ -n "${GITLAB_TOKEN:-}" ]; then
echo "  - GitLab credentials for ArgoCD"
fi
echo "  - Prometheus + Grafana (namespace: monitoring)"
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
echo "  - External-DNS (namespace: external-dns)"
fi
if [ -f "$TUNNEL_CREDS" ]; then
echo "  - Cloudflare Tunnel credentials"
fi
echo ""
echo "GatewayClass available:"
kubectl get gatewayclass 2>/dev/null || echo "  (initializing...)"
echo ""
echo "Next step - Bootstrap ArgoCD (Layer 4):"
echo ""
echo "  kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml"
echo ""
echo "Access services:"
echo ""
echo "  ArgoCD UI:"
echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "     Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "  Grafana:"
echo "     kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "     URL: http://localhost:3000 (admin / admin)"
echo ""
