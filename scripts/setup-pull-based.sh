#!/bin/bash
# Setup Pull-based GitOps with ArgoCD
# This script configures ArgoCD to watch gitops-config repository
# Uses "App of Apps" pattern for automatic management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if exists
if [ -f "$ROOT_DIR/.env" ]; then
    source "$ROOT_DIR/.env"
fi

# Set defaults
GITLAB_GROUP="${GITLAB_GROUP:-gitops-poc-dzha}"
GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "============================================"
echo "  Pull-Based GitOps Setup (ArgoCD)"
echo "============================================"
echo ""

# Check ArgoCD is installed
echo_info "Step 1: Checking ArgoCD..."
if ! kubectl get namespace argocd &> /dev/null; then
    echo_error "ArgoCD is not installed. Run:"
    echo "  ./shared/infrastructure/argocd/setup.sh"
    exit 1
fi

if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server 2>/dev/null | grep -q Running; then
    echo_error "ArgoCD server not running"
    exit 1
fi
echo_info "ArgoCD is running"

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || true

# Step 2: Add repository credentials
echo ""
echo_info "Step 2: Setting up GitLab repository credentials..."

if [[ -z "$GITLAB_TOKEN" ]]; then
    echo_warn "GITLAB_TOKEN not set in environment or .env file"
    echo ""
    echo "ArgoCD needs a GitLab token to access private repositories."
    echo "Create a Personal Access Token with 'read_repository' scope:"
    echo "  https://gitlab.com/-/user_settings/personal_access_tokens"
    echo ""
    read -p "Enter GitLab Token (or press Enter to skip): " GITLAB_TOKEN
fi

if [[ -n "$GITLAB_TOKEN" ]]; then
    # Check if secret already exists
    if kubectl get secret gitlab-repo-creds -n argocd &>/dev/null; then
        echo_warn "Secret 'gitlab-repo-creds' already exists, updating..."
        kubectl delete secret gitlab-repo-creds -n argocd
    fi

    kubectl create secret generic gitlab-repo-creds -n argocd \
        --from-literal=type=git \
        --from-literal=url="https://${GITLAB_HOST}/${GITLAB_GROUP}" \
        --from-literal=username=oauth2 \
        --from-literal=password="$GITLAB_TOKEN"

    kubectl label secret gitlab-repo-creds -n argocd \
        argocd.argoproj.io/secret-type=repo-creds

    echo_info "Repository credentials added for https://${GITLAB_HOST}/${GITLAB_GROUP}"
else
    echo_warn "Skipping credentials setup - add repos manually in ArgoCD UI"
fi

# Brand configuration (default: poc)
BRAND="${BRAND:-poc}"
GITOPS_CONFIG_DIR="$ROOT_DIR/infra/$BRAND/gitops-config"

# Step 3: Apply ArgoCD Project
echo ""
echo_info "Step 3: Creating ArgoCD Project..."
kubectl apply -f "$GITOPS_CONFIG_DIR/argocd/project.yaml"

# Step 4: Apply Bootstrap Application (App of Apps)
echo ""
echo_info "Step 4: Creating Bootstrap Application (App of Apps)..."
kubectl apply -f "$GITOPS_CONFIG_DIR/argocd/bootstrap-app.yaml"

# Step 5: Wait and check
echo ""
echo_info "Step 5: Waiting for initial sync..."
sleep 5

echo ""
echo_info "ArgoCD Applications:"
kubectl get applications -n argocd 2>/dev/null || echo "No applications yet"

echo ""
echo "============================================"
echo_info "Pull-based GitOps setup complete!"
echo "============================================"
echo ""
echo "Access ArgoCD UI:"
echo "  make proxy-argocd"
echo "  Open: http://localhost:8081"
echo ""
if [ -n "$ARGOCD_PASSWORD" ]; then
    echo "Credentials:"
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASSWORD"
    echo ""
fi
echo "Next steps:"
echo "  1. Commit and push infra/$BRAND/gitops-config/argocd/ changes to GitLab"
echo "  2. Switch services to Pull mode: GITOPS_MODE=\"pull\" in .gitlab-ci.yml"
echo "  3. ArgoCD will auto-sync changes within 3 minutes"
echo ""
echo "Check applications:"
echo "  kubectl get applications -n argocd"
echo ""
