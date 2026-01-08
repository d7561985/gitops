#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  ArgoCD Installation"
echo "========================================"

# Add Argo Helm repo
echo_info "Adding Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create namespace
echo_info "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo_info "Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --wait \
  --timeout 10m \
  -f "$SCRIPT_DIR/helm-values.yaml"

# Wait for ArgoCD to be ready
echo_info "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=180s

# Get admin password
echo_info "Getting admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "========================================"
echo_info "ArgoCD installation complete!"
echo "========================================"
echo ""
echo "Access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Open: https://localhost:8080"
echo ""
echo "Credentials:"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""
echo "CLI Login:"
echo "  argocd login localhost:8080 --insecure --username admin --password '$ARGOCD_PASSWORD'"
echo ""
