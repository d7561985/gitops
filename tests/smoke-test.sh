#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
echo_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
echo_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

FAILURES=0

test_check() {
    local name="$1"
    local cmd="$2"

    if eval "$cmd" &> /dev/null; then
        echo_pass "$name"
    else
        echo_fail "$name"
        ((FAILURES++))
    fi
}

echo "========================================"
echo "  GitOps POC Smoke Tests"
echo "========================================"
echo ""

# ============================================
# Infrastructure Tests
# ============================================

echo "--- Infrastructure ---"

test_check "Minikube running" "minikube status"
test_check "kubectl connected" "kubectl cluster-info"

test_check "Vault namespace exists" "kubectl get namespace vault"
test_check "Vault pod running" "kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].status.phase}' | grep -q Running"

test_check "VSO namespace exists" "kubectl get namespace vault-secrets-operator-system"
test_check "VSO pod running" "kubectl get pods -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator -o jsonpath='{.items[0].status.phase}' | grep -q Running"

test_check "ArgoCD namespace exists" "kubectl get namespace argocd"
test_check "ArgoCD server running" "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' | grep -q Running"

echo ""

# ============================================
# Application Tests (if deployed)
# ============================================

echo "--- Applications (dev environment) ---"

SERVICES=("api-gateway" "auth-adapter" "web-grpc" "web-http" "health-demo")

for SERVICE in "${SERVICES[@]}"; do
    NAMESPACE="${SERVICE}-dev"

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        test_check "${SERVICE} namespace" "true"
        test_check "${SERVICE} deployment" "kubectl get deployment ${SERVICE} -n ${NAMESPACE}"
        test_check "${SERVICE} pod running" "kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${SERVICE} -o jsonpath='{.items[0].status.phase}' | grep -q Running"
    else
        echo_info "${SERVICE}: namespace not found (not deployed yet)"
    fi
done

echo ""

# ============================================
# Vault Secrets Tests
# ============================================

echo "--- Vault Secrets ---"

# Start port-forward if not running
if ! nc -z localhost 8200 2>/dev/null; then
    kubectl port-forward svc/vault -n vault 8200:8200 &
    PF_PID=$!
    sleep 2
fi

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

test_check "Vault reachable" "vault status"
test_check "KV secrets engine" "vault secrets list | grep -q 'secret/'"
test_check "Kubernetes auth" "vault auth list | grep -q 'kubernetes/'"

# Check sample secrets
for SERVICE in "api-gateway" "auth-adapter"; do
    test_check "${SERVICE}/dev secret exists" "vault kv get secret/gitops-poc/${SERVICE}/dev/config"
done

# Cleanup port-forward
kill $PF_PID 2>/dev/null || true

echo ""

# ============================================
# Summary
# ============================================

echo "========================================"
if [ $FAILURES -eq 0 ]; then
    echo_pass "All tests passed!"
else
    echo_fail "$FAILURES test(s) failed"
fi
echo "========================================"

exit $FAILURES
