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

# ============================================
# Minikube Status
# ============================================

echo_header "Checking Minikube"

if ! minikube status &> /dev/null; then
    echo_warn "Minikube is not running. Starting..."
    minikube start --cpus 4 --memory 8192 --disk-size 40g
fi

echo_info "Minikube is running"
echo_info "Kubernetes version: $(kubectl version --client --short 2>/dev/null || echo 'unknown')"

# Enable addons
echo_info "Enabling Minikube addons..."
minikube addons enable ingress 2>/dev/null || true
minikube addons enable metrics-server 2>/dev/null || true

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
# Summary
# ============================================

echo ""
echo "========================================"
echo_info "Infrastructure setup complete!"
echo "========================================"
echo ""
echo "Installed components:"
echo "  - Vault (namespace: vault)"
echo "  - Vault Secrets Operator (namespace: vault-secrets-operator-system)"
echo "  - ArgoCD (namespace: argocd)"
echo ""
echo "Next steps:"
echo ""
echo "1. Configure Vault secrets:"
echo "   ./scripts/setup-vault-secrets.sh"
echo ""
echo "2. For Push-based GitOps (GitLab Agent):"
echo "   export GITLAB_AGENT_TOKEN='<your-token>'"
echo "   ./infrastructure/gitlab-agent/setup.sh"
echo ""
echo "3. For Pull-based GitOps (ArgoCD):"
echo "   # Access ArgoCD UI"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   # Add your GitLab repository"
echo "   # Apply ApplicationSet"
echo ""
echo "4. Build local images (for api-gateway, auth-adapter, health-demo):"
echo "   ./scripts/build-local-images.sh"
echo ""
