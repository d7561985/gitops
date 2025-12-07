#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if exists
if [ -f "$ROOT_DIR/.env" ]; then
    source "$ROOT_DIR/.env"
fi

# Set defaults
GITLAB_GROUP="${GITLAB_GROUP:-gitops-poc}"
GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"
SERVICES="${SERVICES:-api-gateway auth-adapter web-grpc web-http health-demo}"

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

# Apply ArgoCD Project
echo_info "Creating ArgoCD Project..."
kubectl apply -f "$ROOT_DIR/gitops-config/argocd/project.yaml"

# Apply ApplicationSet
echo_info "Creating ArgoCD ApplicationSet..."
kubectl apply -f "$ROOT_DIR/gitops-config/argocd/applicationset.yaml"

echo ""
echo "========================================"
echo_info "Pull-based GitOps setup complete!"
echo "========================================"
echo ""
echo "IMPORTANT: Before apps can sync, you need to:"
echo ""
echo "1. Create GitLab repositories for each service:"
for SERVICE in $SERVICES; do
    echo "   - ${GITLAB_HOST}/${GITLAB_GROUP}/${SERVICE}"
done
echo ""
echo "2. Copy service files from this repo:"
echo "   cp -r services/api-gateway/* /path/to/api-gateway/"
echo ""
echo "3. Add GitLab repos to ArgoCD (if private):"
echo "   argocd repocreds add https://${GITLAB_HOST}/${GITLAB_GROUP} \\"
echo "     --username git --password <token>"
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
