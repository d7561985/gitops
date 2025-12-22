#!/bin/bash
# =============================================================================
# External-DNS Setup Script
# =============================================================================
# Устанавливает external-dns для автоматического управления DNS записями
# Поддерживает: CloudFlare, AWS Route53, Google Cloud DNS, Azure DNS
#
# Источник: https://github.com/kubernetes-sigs/external-dns
#
# Использование:
#   ./setup.sh                    # Загружает токен из .env
#   CLOUDFLARE_API_TOKEN=xxx ./setup.sh  # Явно указать токен
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACE="external-dns"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Проверка зависимостей
# -----------------------------------------------------------------------------
check_dependencies() {
    log_info "Проверка зависимостей..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl не найден"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm не найден"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Загрузка переменных окружения из .env
# -----------------------------------------------------------------------------
load_env() {
    # Загружаем .env из корня проекта если токен не передан явно
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        if [[ -f "${ROOT_DIR}/.env" ]]; then
            log_info "Загрузка конфигурации из ${ROOT_DIR}/.env"
            # shellcheck source=/dev/null
            source "${ROOT_DIR}/.env"
        fi
    fi

    # Проверяем наличие токена
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        log_error "CLOUDFLARE_API_TOKEN не установлен"
        echo ""
        log_info "Варианты установки:"
        echo "  1. Добавьте в .env файл: CLOUDFLARE_API_TOKEN=\"your-token\""
        echo "  2. Или передайте явно: CLOUDFLARE_API_TOKEN=xxx ./setup.sh"
        echo ""
        log_info "Создайте API Token: https://dash.cloudflare.com/profile/api-tokens"
        log_info "Permissions: Zone:Zone:Read, Zone:DNS:Edit"
        exit 1
    fi

    log_info "CLOUDFLARE_API_TOKEN загружен"
}

# -----------------------------------------------------------------------------
# Создание namespace и secret
# -----------------------------------------------------------------------------
create_namespace_and_secret() {
    log_info "Создание namespace ${NAMESPACE}..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    log_info "Создание secret с CloudFlare API Token..."
    kubectl create secret generic cloudflare-api-credentials \
        --namespace "${NAMESPACE}" \
        --from-literal=cloudflare_api_token="${CLOUDFLARE_API_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f -
}

# -----------------------------------------------------------------------------
# Установка external-dns через Helm
# -----------------------------------------------------------------------------
install_external_dns() {
    log_info "Добавление Helm repo..."
    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ 2>/dev/null || true
    helm repo update

    log_info "Установка external-dns..."
    helm upgrade --install external-dns external-dns/external-dns \
        --namespace "${NAMESPACE}" \
        --values "${SCRIPT_DIR}/helm-values.yaml" \
        --wait \
        --timeout 5m
}

# -----------------------------------------------------------------------------
# Проверка установки
# -----------------------------------------------------------------------------
verify_installation() {
    log_info "Проверка установки..."

    kubectl wait --for=condition=available deployment/external-dns \
        --namespace "${NAMESPACE}" \
        --timeout=120s

    log_info "External-DNS успешно установлен!"
    echo ""
    log_info "Проверить логи: kubectl logs -f deployment/external-dns -n ${NAMESPACE}"
    log_info "Проверить DNS записи: kubectl get dnsendpoints -A"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    log_info "=== External-DNS Setup ==="

    check_dependencies
    load_env
    create_namespace_and_secret
    install_external_dns
    verify_installation

    log_info "=== Setup Complete ==="
}

main "$@"
