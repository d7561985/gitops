#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env (handles single-quoted values)
if [ -f "$ROOT_DIR/.env" ]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            export "$key=$value"
        fi
    done < "$ROOT_DIR/.env"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"
REGISTRY_HOST="registry.${GITLAB_HOST}"
SECRET_NAME="regsecret"
NAMESPACES="${NAMESPACES:-poc-dev poc-staging poc-prod}"

echo "========================================"
echo "  GitLab Registry Secret Setup"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Registry:    $REGISTRY_HOST"
echo "  Secret name: $SECRET_NAME"
echo "  Namespaces:  $NAMESPACES"
echo ""

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

echo_info "Creating registry secrets..."

for NS in $NAMESPACES; do
    # Create namespace if not exists
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

    # Delete existing secret if exists (to update credentials)
    kubectl delete secret "$SECRET_NAME" -n "$NS" 2>/dev/null || true

    # Create docker-registry secret
    kubectl create secret docker-registry "$SECRET_NAME" \
        --namespace="$NS" \
        --docker-server="$REGISTRY_HOST" \
        --docker-username="$GITLAB_DEPLOY_TOKEN_USER" \
        --docker-password="$GITLAB_DEPLOY_TOKEN"

    echo_info "  Created: $NS/$SECRET_NAME"
done

echo ""
echo "========================================"
echo_info "Registry setup complete!"
echo "========================================"
echo ""
echo "Services must declare imagePullSecrets in their values:"
echo ""
echo "  # .cicd/default.yaml"
echo "  imagePullSecrets:"
echo "    - name: regsecret"
echo ""
