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
chmod +x "$ROOT_DIR/infrastructure/gateway-api/setup.sh"
"$ROOT_DIR/infrastructure/gateway-api/setup.sh"

# ============================================
# Install Cilium CNI with Gateway API
# ============================================

echo_header "Installing Cilium CNI"
chmod +x "$ROOT_DIR/infrastructure/cilium/setup.sh"
"$ROOT_DIR/infrastructure/cilium/setup.sh"

# Wait for networking to stabilize
echo_info "Waiting for cluster networking to stabilize..."
sleep 10

# ============================================
# Install cert-manager
# ============================================

echo_header "Installing cert-manager"
chmod +x "$ROOT_DIR/infrastructure/cert-manager/setup.sh"
"$ROOT_DIR/infrastructure/cert-manager/setup.sh"

# ============================================
# Install Vault + VSO
# ============================================

echo_header "Installing Vault + VSO"
chmod +x "$ROOT_DIR/infrastructure/vault/setup.sh"
"$ROOT_DIR/infrastructure/vault/setup.sh"

# ============================================
# Install ArgoCD
# ============================================

echo_header "Installing ArgoCD"
chmod +x "$ROOT_DIR/infrastructure/argocd/setup.sh"
"$ROOT_DIR/infrastructure/argocd/setup.sh"

# ============================================
# Install Monitoring (Prometheus + Grafana)
# ============================================

echo_header "Installing Monitoring Stack"
chmod +x "$ROOT_DIR/infrastructure/monitoring/setup.sh"
"$ROOT_DIR/infrastructure/monitoring/setup.sh"

# ============================================
# Create Vault Admin Token Secret
# ============================================

echo_header "Creating Vault admin token secret"

# Get token from vault-keys secret (created by vault/setup.sh)
VAULT_TOKEN=$(kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo "")

# Fallback to local file
if [ -z "$VAULT_TOKEN" ] && [ -f "$ROOT_DIR/infrastructure/vault/.vault-keys" ]; then
    source "$ROOT_DIR/infrastructure/vault/.vault-keys"
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
echo "  - ArgoCD (namespace: argocd)"
echo "  - Prometheus + Grafana (namespace: monitoring)"
echo ""
echo "GatewayClass available:"
kubectl get gatewayclass 2>/dev/null || echo "  (none yet - Cilium may still be initializing)"
echo ""
echo "Next steps:"
echo ""
echo "1. (Optional) Setup CloudFlare for automatic TLS:"
echo "   export CLOUDFLARE_API_TOKEN=your-token"
echo "   ./infrastructure/cert-manager/setup.sh"
echo ""
echo "2. Setup registry secrets (for GitLab Container Registry):"
echo "   ./scripts/setup-registry-secret.sh"
echo ""
echo "3. Add GitLab repo credentials to ArgoCD:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   # Get password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "4. Apply bootstrap (starts everything automatically):"
echo "   kubectl apply -f gitops-config/argocd/project.yaml"
echo "   kubectl apply -f gitops-config/argocd/bootstrap-app.yaml"
echo ""
echo "5. Access Hubble UI (network observability):"
echo "   cilium hubble ui"
echo ""
echo "6. Access Grafana (metrics dashboards):"
echo "   kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "   # URL: http://localhost:3000 (admin / admin)"
echo ""
echo "7. Access Prometheus (raw metrics):"
echo "   kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090"
echo ""
