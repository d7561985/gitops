# Platform Architecture Audit

## Обзор

Данная директория содержит концептуальную документацию по архитектуре GitOps-платформы для команд. Все документы основаны на аудите реальной кодовой базы и содержат ссылки на соответствующие файлы.

---

## Структура документации

| # | Документ | Описание | Аудитория |
|---|----------|----------|-----------|
| 00 | [Executive Summary](./00-executive-summary.md) | Высокоуровневый обзор для руководства | Руководители, архитекторы |
| 01 | [Platform Architecture](./01-platform-architecture.md) | Детальная архитектура платформы | SRE, Platform Engineers |
| 02 | [GitOps Principles](./02-gitops-principles.md) | Принципы GitOps и workflow | Все команды |
| 03 | [Developer Experience](./03-developer-experience.md) | SDLC и k8app | Разработчики |
| 04 | [API Standards](./04-api-standards.md) | Buf, ConnectRPC, proto | API владельцы |
| 05 | [Team Model](./05-team-model.md) | Роли, RACI, доступы | Менеджеры, Tech Leads |
| 06 | [Observability](./06-observability.md) | eBPF, Hubble, Prometheus | SRE, разработчики |
| 07 | [Multi-Tenancy](./07-multi-tenancy.md) | Environments, brands, Vault isolation | Архитекторы, SRE |

---

## Быстрая навигация по темам

### Для руководителей

- [Executive Summary](./00-executive-summary.md) — начните здесь
- [Team Model: Quick Reference](./05-team-model.md#quick-reference) — кто за что отвечает

### Для архитекторов

- [Platform Architecture](./01-platform-architecture.md) — полная архитектура
- [API Standards](./04-api-standards.md) — стандарты API

### Для разработчиков

- [Developer Experience](./03-developer-experience.md) — как деплоить сервисы
- [GitOps Principles: Configuration](./02-gitops-principles.md#configuration-separation) — default.yaml vs env.yaml

### Для SRE/Platform

- [Platform Architecture: Components](./01-platform-architecture.md#компоненты-платформы) — все компоненты
- [Multi-Tenancy](./07-multi-tenancy.md) — environments, brands, Vault isolation
- [Observability](./06-observability.md) — мониторинг и отладка

---

## Ключевые принципы платформы

### 1. Декларативность
Вся инфраструктура описана как код в Git.

**Источник:** [`gitops-config/platform/core.yaml`](../gitops-config/platform/core.yaml)

### 2. GitOps Pull-Based
ArgoCD периодически сверяет и синхронизирует состояние кластера с Git.

**Источник:** [`gitops-config/argocd/`](../gitops-config/argocd/)

### 3. Агностичность к окружениям
Один код — dev/staging/prod через .cicd/ overlays.

**Источник:** [`docs/multi-tenancy-guide.md`](../docs/multi-tenancy-guide.md)

### 4. Self-Service для команд
Продуктовые команды самостоятельно управляют деплоями и секретами.

**Источник:** [`docs/embodiment/access-management.md`](../docs/embodiment/access-management.md)

---

## Связанная документация

| Документ | Описание |
|----------|----------|
| [`README.md`](../README.md) | Главная документация проекта |
| [`docs/PREFLIGHT-CHECKLIST.md`](../docs/PREFLIGHT-CHECKLIST.md) | Чеклист настройки |
| [`docs/new-service-guide.md`](../docs/new-service-guide.md) | Добавление нового сервиса |
| [`docs/domain-mirrors-guide.md`](../docs/domain-mirrors-guide.md) | Зеркальные домены |
| [`docs/service-groups-guide.md`](../docs/service-groups-guide.md) | Публикация infra-сервисов (ArgoCD, Grafana, Vault) |
| [`docs/preview-environments-guide.md`](../docs/preview-environments-guide.md) | Preview для MR с JIRA тегами |
| [`docs/embodiment/`](../docs/embodiment/) | Расширенные топики |

---

## Как читать эту документацию

1. **Начните с [Executive Summary](./00-executive-summary.md)** — общее понимание
2. **Прочитайте документ по вашей роли** — см. "Быстрая навигация"
3. **Переходите по ссылкам на исходный код** — все утверждения подкреплены

---

*Дата аудита: 2025-12-21*
*Источник: GitOps POC кодовая база*
