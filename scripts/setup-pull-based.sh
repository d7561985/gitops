#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  Pull-Based GitOps Setup (ArgoCD)"
echo "========================================"

# Check ArgoCD is installed
if ! kubectl get namespace argocd &> /dev/null; then
    echo_error "ArgoCD is not installed. Run ./scripts/setup-infrastructure.sh first"
    exit 1
fi

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || true

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo_warn "Could not get ArgoCD password. It may have been deleted."
fi

# Check for REPO_URL
if [ -z "$REPO_URL" ]; then
    echo_warn "REPO_URL is not set. Using placeholder."
    echo ""
    echo "To properly configure, set your GitLab repository URL:"
    echo "  export REPO_URL='https://gitlab.com/your-username/gitops-poc.git'"
    echo "  $0"
    echo ""
    REPO_URL="https://gitlab.com/REPLACE_ME/gitops-poc.git"
fi

# Apply ArgoCD Project
echo_info "Creating ArgoCD Project..."
kubectl apply -f "$ROOT_DIR/gitops/pull-based/project.yaml"

# Update ApplicationSet with repo URL and apply
echo_info "Creating ArgoCD ApplicationSet..."
sed "s|REPO_URL_PLACEHOLDER|$REPO_URL|g" \
    "$ROOT_DIR/gitops/pull-based/applicationset.yaml" | kubectl apply -f -

echo ""
echo "========================================"
echo_info "Pull-based GitOps setup complete!"
echo "========================================"
echo ""
echo "Access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Open: https://localhost:8080"
echo ""
if [ -n "$ARGOCD_PASSWORD" ]; then
    echo "Credentials:"
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASSWORD"
    echo ""
fi
echo "Check applications:"
echo "  argocd app list"
echo "  kubectl get applications -n argocd"
echo ""
echo "ApplicationSet will create apps for each service/environment:"
echo "  - api-gateway-dev, api-gateway-staging, api-gateway-prod"
echo "  - auth-adapter-dev, auth-adapter-staging, auth-adapter-prod"
echo "  - web-grpc-dev, web-grpc-staging, web-grpc-prod"
echo "  - web-http-dev, web-http-staging, web-http-prod"
echo "  - health-demo-dev, health-demo-staging, health-demo-prod"
echo ""
