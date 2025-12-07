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
    echo "  1. Go to: https://${GITLAB_HOST}/${GITLAB_GROUP}/gitops-config"
    echo "  2. Operate → Kubernetes clusters → Connect a cluster (agent)"
    echo "  3. Enter agent name: minikube-agent"
    echo "  4. Click 'Create and register'"
    echo "  5. Copy the token (shown only once!)"
    echo ""
    echo "Then either:"
    echo "  a) Add to .env file:"
    echo "     GITLAB_AGENT_TOKEN=\"glagent-xxxxxx-xxxxxxxxxxxxxxxxx\""
    echo ""
    echo "  b) Or export and run:"
    echo "     export GITLAB_AGENT_TOKEN='glagent-xxxxxx-xxxxxxxxxxxxxxxxx'"
    echo "     $0"
    exit 1
fi

echo_info "Using GITLAB_AGENT_TOKEN from environment"

# Export token for child script
export GITLAB_AGENT_TOKEN

# Install GitLab Agent
echo_info "Installing GitLab Agent..."
chmod +x "$ROOT_DIR/infrastructure/gitlab-agent/setup.sh"
"$ROOT_DIR/infrastructure/gitlab-agent/setup.sh"

echo ""
echo "========================================"
echo_info "Push-based GitOps setup complete!"
echo "========================================"
echo ""
echo "Verify agent is running:"
echo "  kubectl get pods -n gitlab-agent"
echo ""
echo "Check agent logs:"
echo "  kubectl logs -n gitlab-agent -l app.kubernetes.io/name=gitlab-agent"
echo ""
echo "In GitLab UI, agent should show 'Connected':"
echo "  https://${GITLAB_HOST}/${GITLAB_GROUP}/gitops-config/-/cluster_agents"
echo ""
echo "To enable Push-based deployments in CI/CD:"
echo "  Set GITOPS_MODE=push in GitLab Group → Settings → CI/CD → Variables"
echo ""
echo "CI will use context:"
echo "  ${GITLAB_GROUP}/gitops-config:minikube-agent"
echo ""
