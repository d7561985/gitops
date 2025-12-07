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

GITLAB_GROUP="${GITLAB_GROUP:-gitops-poc}"
GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"
REGISTRY_HOST="registry.${GITLAB_HOST}"

echo "========================================"
echo "  GitLab Registry Secret Setup"
echo "========================================"
echo ""
echo "This script creates imagePullSecrets for Kubernetes"
echo "to pull images from GitLab Container Registry."
echo ""

# Check for credentials
if [ -z "$GITLAB_DEPLOY_TOKEN_USER" ] || [ -z "$GITLAB_DEPLOY_TOKEN" ]; then
    echo_warn "GITLAB_DEPLOY_TOKEN_USER and GITLAB_DEPLOY_TOKEN not set"
    echo ""
    echo "To create a Deploy Token:"
    echo "  1. Go to GitLab: ${GITLAB_HOST}/${GITLAB_GROUP}/-/settings/repository"
    echo "  2. Expand 'Deploy tokens'"
    echo "  3. Create token with 'read_registry' scope"
    echo "  4. Copy username and token"
    echo ""
    echo "Then run:"
    echo "  export GITLAB_DEPLOY_TOKEN_USER='gitlab+deploy-token-xxxxx'"
    echo "  export GITLAB_DEPLOY_TOKEN='gldt-xxxxxxxxxxxx'"
    echo "  $0"
    echo ""

    # Interactive mode
    read -p "Or enter Deploy Token username now (or press Enter to exit): " GITLAB_DEPLOY_TOKEN_USER
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

echo ""
echo "Configuration:"
echo "  Registry:  $REGISTRY_HOST"
echo "  Username:  $GITLAB_DEPLOY_TOKEN_USER"
echo "  Group:     $GITLAB_GROUP"
echo ""

# Services and environments
SERVICES="${SERVICES:-api-gateway auth-adapter web-grpc web-http health-demo}"
ENVIRONMENTS="${ENVIRONMENTS:-dev staging prod}"

# k8app chart uses hardcoded secret name "regsecret" with deploySecretHarbor/deploySecretNexus
SECRET_NAME="regsecret"

echo_info "Creating registry secrets..."

for SERVICE in $SERVICES; do
    for ENV in $ENVIRONMENTS; do
        NAMESPACE="${SERVICE}-${ENV}"

        # Create namespace if not exists
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

        # Create or update secret
        kubectl create secret docker-registry "$SECRET_NAME" \
            --namespace="$NAMESPACE" \
            --docker-server="$REGISTRY_HOST" \
            --docker-username="$GITLAB_DEPLOY_TOKEN_USER" \
            --docker-password="$GITLAB_DEPLOY_TOKEN" \
            --docker-email="deploy@${GITLAB_GROUP}.local" \
            --dry-run=client -o yaml | kubectl apply -f -

        echo_info "Created secret in namespace: $NAMESPACE"
    done
done

echo ""
echo "========================================"
echo_info "Registry secrets created!"
echo "========================================"
echo ""
echo "Secrets created in namespaces:"
for SERVICE in $SERVICES; do
    for ENV in $ENVIRONMENTS; do
        echo "  - ${SERVICE}-${ENV}"
    done
done
echo ""
echo "To use in deployments, add to your Helm values:"
echo ""
echo "  imagePullSecrets:"
echo "    - name: $SECRET_NAME"
echo ""
echo "Or patch the default ServiceAccount:"
echo "  kubectl patch serviceaccount default -n <namespace> \\"
echo "    -p '{\"imagePullSecrets\": [{\"name\": \"$SECRET_NAME\"}]}'"
echo ""
