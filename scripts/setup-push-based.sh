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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  Push-Based GitOps Setup (GitLab Agent)"
echo "========================================"

# Check for token
if [ -z "$GITLAB_AGENT_TOKEN" ]; then
    echo_error "GITLAB_AGENT_TOKEN is not set!"
    echo ""
    echo "To get the token:"
    echo "  1. Push this repo to GitLab.com (or self-managed GitLab)"
    echo "  2. Go to your GitLab project"
    echo "  3. Navigate to: Infrastructure → Kubernetes clusters"
    echo "  4. Click 'Connect a cluster' → Create agent"
    echo "  5. Name it: gitops-poc"
    echo "  6. Copy the registration token"
    echo ""
    echo "Then run:"
    echo "  export GITLAB_AGENT_TOKEN='glagent-xxx...'"
    echo "  $0"
    exit 1
fi

# Install GitLab Agent
echo_info "Installing GitLab Agent..."
chmod +x "$ROOT_DIR/infrastructure/gitlab-agent/setup.sh"
"$ROOT_DIR/infrastructure/gitlab-agent/setup.sh"

echo ""
echo "========================================"
echo_info "Push-based GitOps setup complete!"
echo "========================================"
echo ""
echo "Required files in your GitLab repo:"
echo ""
echo "  .gitlab/agents/minikube-agent/config.yaml:"
echo "  ────────────────────────────────────────"
cat "$ROOT_DIR/infrastructure/gitlab-agent/config.yaml"
echo ""
echo "  ────────────────────────────────────────"
echo ""
echo "  .gitlab-ci.yml example:"
echo "  ────────────────────────────────────────"
echo "  See: services/api-gateway/.gitlab-ci.yml (set GITOPS_MODE: push)"
echo ""
echo "Test the connection:"
echo "  kubectl get pods -n gitlab-agent"
echo ""
echo "Use in CI:"
echo "  kubectl config use-context ${GITLAB_GROUP}/gitops-config:minikube-agent"
echo ""
