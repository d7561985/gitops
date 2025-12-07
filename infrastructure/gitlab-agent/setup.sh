#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "  GitLab Agent Installation"
echo "========================================"

# Check for token
if [ -z "$GITLAB_AGENT_TOKEN" ]; then
    echo_error "GITLAB_AGENT_TOKEN is not set!"
    echo ""
    echo "To get the token:"
    echo "  1. Go to your GitLab project"
    echo "  2. Navigate to: Infrastructure → Kubernetes clusters"
    echo "  3. Click 'Connect a cluster'"
    echo "  4. Select agent name (e.g., 'minikube-agent')"
    echo "  5. Copy the registration token"
    echo ""
    echo "Then run:"
    echo "  export GITLAB_AGENT_TOKEN='your-token-here'"
    echo "  $0"
    exit 1
fi

# Add GitLab Helm repo
echo_info "Adding GitLab Helm repository..."
helm repo add gitlab https://charts.gitlab.io
helm repo update

# Create namespace
echo_info "Creating gitlab-agent namespace..."
kubectl create namespace gitlab-agent --dry-run=client -o yaml | kubectl apply -f -

# Install GitLab Agent
echo_info "Installing GitLab Agent..."
helm upgrade --install gitlab-agent gitlab/gitlab-agent \
  --namespace gitlab-agent \
  --set config.token="$GITLAB_AGENT_TOKEN" \
  --wait \
  --timeout 5m \
  -f "$SCRIPT_DIR/helm-values.yaml"

# Wait for agent to be ready
echo_info "Waiting for GitLab Agent to be ready..."
kubectl wait --for=condition=Ready pods -l app=gitlab-agent \
  -n gitlab-agent --timeout=120s

echo ""
echo "========================================"
echo_info "GitLab Agent installation complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Create agent config in your GitLab repo:"
echo "     .gitlab/agents/minikube-agent/config.yaml"
echo ""
echo "  2. Copy the template config:"
echo "     cp $SCRIPT_DIR/config.yaml .gitlab/agents/minikube-agent/config.yaml"
echo ""
echo "  3. Update the project IDs in config.yaml"
echo ""
echo "  4. Use in .gitlab-ci.yml:"
echo "     script:"
echo "       - kubectl config use-context your-group/gitops-poc:minikube-agent"
echo "       - helm upgrade --install ..."
echo ""
