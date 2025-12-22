#!/bin/bash
# =============================================================================
# CloudFlare Tunnel Setup
# =============================================================================
# Создаёт tunnel и деплоит cloudflared в Kubernetes.
# Ingress rules управляются через ConfigMap (GitOps).
#
# Если у вас уже есть tunnel в remotely-managed режиме (настроен через Dashboard),
# используйте migrate-to-locally-managed.sh для миграции.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

NAMESPACE="cloudflare"
TUNNEL_NAME="${1:-gitops-platform}"

echo "========================================"
echo "  CloudFlare Tunnel (Locally-Managed)"
echo "========================================"
echo ""
echo "Этот скрипт создаёт новый tunnel в locally-managed режиме."
echo "Ingress rules будут управляться через Kubernetes ConfigMap."
echo ""

# -----------------------------------------------------------------------------
# Шаг 1: Проверка cloudflared CLI
# -----------------------------------------------------------------------------
log_step "1/6: Проверка cloudflared CLI"

if ! command -v cloudflared &> /dev/null; then
    log_error "cloudflared CLI не найден"
    echo ""
    echo "Установите:"
    echo "  macOS:  brew install cloudflared"
    echo "  Linux:  https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
    echo ""
    exit 1
fi
log_info "cloudflared: $(cloudflared --version)"

# -----------------------------------------------------------------------------
# Шаг 2: Авторизация в CloudFlare
# -----------------------------------------------------------------------------
log_step "2/6: Авторизация в CloudFlare"

if [ ! -f ~/.cloudflared/cert.pem ]; then
    log_info "Требуется авторизация. Откроется браузер..."
    cloudflared tunnel login
else
    log_info "Уже авторизован (cert.pem найден)"
fi

# -----------------------------------------------------------------------------
# Шаг 3: Создание tunnel
# -----------------------------------------------------------------------------
log_step "3/6: Создание tunnel '$TUNNEL_NAME'"

# Проверяем существует ли уже
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    log_warn "Tunnel '$TUNNEL_NAME' уже существует"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
else
    cloudflared tunnel create "$TUNNEL_NAME"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    log_info "Tunnel создан с ID: $TUNNEL_ID"
fi

CREDENTIALS_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"

if [ ! -f "$CREDENTIALS_FILE" ]; then
    log_error "Credentials file не найден: $CREDENTIALS_FILE"
    exit 1
fi
log_info "Credentials: $CREDENTIALS_FILE"

# -----------------------------------------------------------------------------
# Шаг 4: Создание Kubernetes ресурсов
# -----------------------------------------------------------------------------
log_step "4/6: Создание Kubernetes namespace и secrets"

# Namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Secret с credentials.json
kubectl create secret generic cloudflared-credentials \
    --namespace "$NAMESPACE" \
    --from-file=credentials.json="$CREDENTIALS_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "Secret 'cloudflared-credentials' создан"

# -----------------------------------------------------------------------------
# Шаг 5: Вывод tunnelId для values.yaml
# -----------------------------------------------------------------------------
log_step "5/6: Конфигурация"

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║  ВАЖНО: Добавьте tunnelId в values.yaml                                   ║"
echo "╠═══════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                           ║"
echo "║  # infra/poc/gitops-config/platform/base.yaml                              ║"
echo "║  ingress:                                                                 ║"
echo "║    provider: cloudflare-tunnel                                            ║"
echo "║    cloudflare:                                                            ║"
echo "║      enabled: true                                                        ║"
printf "║      tunnelId: \"%-54s\" ║\n" "$TUNNEL_ID"
echo "║                                                                           ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Сохраним в файл для удобства
echo "$TUNNEL_ID" > "$SCRIPT_DIR/.tunnel-id"
log_info "Tunnel ID сохранён в: $SCRIPT_DIR/.tunnel-id"

# -----------------------------------------------------------------------------
# Шаг 6: Деплой cloudflared
# -----------------------------------------------------------------------------
log_step "6/6: Деплой cloudflared"

kubectl apply -f "$SCRIPT_DIR/deployment.yaml"

echo ""
log_info "Ожидание запуска cloudflared..."
kubectl wait --for=condition=Available deployment/cloudflared \
    -n "$NAMESPACE" --timeout=120s || true

echo ""
echo "========================================"
echo -e "${GREEN}✓ CloudFlare Tunnel готов!${NC}"
echo "========================================"
echo ""
echo "Следующие шаги:"
echo ""
echo "  1. Добавьте tunnelId в values.yaml (см. выше)"
echo ""
echo "  2. Commit и push:"
echo "     cd infra/poc/gitops-config"
echo "     git add . && git commit -m 'feat: add cloudflare tunnel id'"
echo "     git push"
echo ""
echo "  3. Синхронизируйте ArgoCD:"
echo "     argocd app sync platform-ingress --grpc-web"
echo ""
echo "  4. Проверьте статус:"
echo "     kubectl logs -n $NAMESPACE -l app=cloudflared -f"
echo ""
echo "Tunnel ID: $TUNNEL_ID"
echo ""
