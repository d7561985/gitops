#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env
if [ -f "$ROOT_DIR/.env" ]; then
    source "$ROOT_DIR/.env"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration from .env
GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"
REGISTRY_HOST="registry.${GITLAB_HOST}"
ENVIRONMENTS="${ENVIRONMENTS:-dev staging prod}"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-poc}"

# k8app chart uses hardcoded secret name "regsecret"
SECRET_NAME="regsecret"

echo "========================================"
echo "  GitLab Registry Secret Setup"
echo "========================================"
echo ""
echo "This script creates imagePullSecrets and patches default ServiceAccount"
echo "so all pods automatically inherit registry credentials."
echo ""
echo "Configuration:"
echo "  Registry:         $REGISTRY_HOST"
echo "  Secret name:      $SECRET_NAME"
echo "  Namespace prefix: $NAMESPACE_PREFIX"
echo "  Environments:     $ENVIRONMENTS"
echo ""

# Check for credentials
if [ -z "$GITLAB_DEPLOY_TOKEN_USER" ] || [ -z "$GITLAB_DEPLOY_TOKEN" ]; then
    echo_warn "GITLAB_DEPLOY_TOKEN_USER and GITLAB_DEPLOY_TOKEN not set"
    echo ""
    echo "To create a Deploy Token:"
    echo "  1. Go to GitLab: Settings → Repository → Deploy tokens"
    echo "  2. Create token with 'read_registry' scope"
    echo "  3. Add to .env or export:"
    echo ""
    echo "     GITLAB_DEPLOY_TOKEN_USER='gitlab+deploy-token-xxxxx'"
    echo "     GITLAB_DEPLOY_TOKEN='gldt-xxxxxxxxxxxx'"
    echo ""

    # Interactive mode
    read -p "Enter Deploy Token username (or press Enter to exit): " GITLAB_DEPLOY_TOKEN_USER
    if [ -z "$GITLAB_DEPLOY_TOKEN_USER" ]; then
        exit 1
    fi
    read -s -p "Enter Deploy Token: " GITLAB_DEPLOY_TOKEN
    echo ""

    if [ -z "$GITLAB_DEPLOY_TOKEN" ]; then
        echo_error "Token cannot be empty"
        exit 1
    fi
fi

echo_info "Creating registry secrets and patching ServiceAccounts..."
echo ""

for ENV in $ENVIRONMENTS; do
    if [ -n "$NAMESPACE_PREFIX" ]; then
        NAMESPACE="${NAMESPACE_PREFIX}-${ENV}"
    else
        NAMESPACE="${ENV}"
    fi

    echo_info "Processing namespace: $NAMESPACE"

    # Create namespace if not exists
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

    # Delete existing secret if exists (to update credentials)
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true

    # Create docker-registry secret
    kubectl create secret docker-registry "$SECRET_NAME" \
        --namespace="$NAMESPACE" \
        --docker-server="$REGISTRY_HOST" \
        --docker-username="$GITLAB_DEPLOY_TOKEN_USER" \
        --docker-password="$GITLAB_DEPLOY_TOKEN"

    echo_info "  Created secret: $SECRET_NAME"

    # Patch default ServiceAccount to use this secret
    # This makes all pods in namespace automatically use imagePullSecrets
    kubectl patch serviceaccount default -n "$NAMESPACE" \
        -p "{\"imagePullSecrets\": [{\"name\": \"$SECRET_NAME\"}]}" 2>/dev/null || \
    kubectl patch serviceaccount default -n "$NAMESPACE" \
        --type='json' \
        -p="[{\"op\": \"add\", \"path\": \"/imagePullSecrets\", \"value\": [{\"name\": \"$SECRET_NAME\"}]}]"

    echo_info "  Patched default ServiceAccount with imagePullSecrets"
    echo ""
done

echo "========================================"
echo_info "Registry setup complete!"
echo "========================================"
echo ""
echo "Created namespaces and secrets:"
for ENV in $ENVIRONMENTS; do
    if [ -n "$NAMESPACE_PREFIX" ]; then
        echo "  - ${NAMESPACE_PREFIX}-${ENV}/$SECRET_NAME"
    else
        echo "  - ${ENV}/$SECRET_NAME"
    fi
done
echo ""
echo "All pods using 'default' ServiceAccount will automatically"
echo "have access to GitLab Container Registry."
echo ""
echo "Note: k8app chart also supports 'deploySecretHarbor: true'"
echo "which explicitly adds imagePullSecrets to deployments."
echo ""
