#!/bin/bash
# Bootstrap script for Talos Kubernetes cluster
# Usage: ./shared/bootstrap/bootstrap.sh
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - helm v3 installed
#
# This installs:
#   1. Gateway API CRDs
#   2. Cilium CNI
#   3. ArgoCD

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Versions (verified December 2024)
# See: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
CILIUM_VERSION="1.18.5"       # Latest stable (Dec 18, 2024)
ARGOCD_VERSION="9.2.3"        # Latest stable (Dec 28, 2024) - ArgoCD v3.0
GATEWAY_API_VERSION="v1.2.0"  # Required by Cilium 1.18.x

echo "=== Talos Bootstrap ==="
echo "Cilium: $CILIUM_VERSION"
echo "ArgoCD: $ARGOCD_VERSION"
echo "Gateway API: $GATEWAY_API_VERSION"
echo ""

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm not found"; exit 1; }

# Check cluster access
echo "Checking cluster access..."
kubectl cluster-info || { echo "Cannot connect to cluster"; exit 1; }

# 1. Gateway API CRDs
echo ""
echo "=== Installing Gateway API CRDs ==="
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

# 2. ArgoCD namespace
echo ""
echo "=== Creating argocd namespace ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 3. Cilium CNI
echo ""
echo "=== Installing Cilium CNI ==="
helm repo add cilium https://helm.cilium.io/ --force-update
helm upgrade --install cilium cilium/cilium \
  --version "$CILIUM_VERSION" \
  --namespace kube-system \
  --values "$SCRIPT_DIR/cilium/values.yaml" \
  --wait

# 4. ArgoCD
echo ""
echo "=== Installing ArgoCD ==="
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm upgrade --install argocd argo/argo-cd \
  --version "$ARGOCD_VERSION" \
  --namespace argocd \
  --values "$SCRIPT_DIR/argocd/values.yaml" \
  --wait

# 5. Wait for pods
echo ""
echo "=== Waiting for pods to be ready ==="
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s

# ArgoCD: wait only for main components (exclude init jobs)
echo "Waiting for ArgoCD components..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-redis -n argocd --timeout=300s

echo ""
echo "=== Bootstrap complete! ==="
echo ""
echo "Next steps:"
echo "  kubectl apply -f infra/poc/gitops-config/argocd/bootstrap-app.yaml"
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
