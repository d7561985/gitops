# k8app Helm Chart — Рекомендации по улучшению Vault интеграции

## Проблема

Текущая реализация Vault в k8app (`templates/vault-crd.yaml`) использует кастомный CRD:

```yaml
apiVersion: <custom>/v1
kind: Vault
spec:
  path: secret/infra/{namespace}/{project}/{environment}
  type: "KEYVALUEV2"
```

Этот CRD требует наличия проприетарного контроллера, который:
1. Не доступен публично
2. Не совместим со стандартными решениями (VSO, ESO)
3. Создаёт vendor lock-in

## Рекомендация

Заменить кастомный Vault CRD на поддержку **HashiCorp Vault Secrets Operator (VSO)** — официального решения от HashiCorp.

### Преимущества VSO

| Аспект | Кастомный CRD | VSO |
|--------|---------------|-----|
| Поддержка | Внутренняя команда | HashiCorp (GA с 2023) |
| Документация | Отсутствует | Полная официальная |
| Community | Нет | Активное |
| Dynamic Secrets | ? | Да |
| Secret Rotation | ? | Да, автоматическая |
| Мониторинг | ? | Prometheus metrics |

### Источники
- [Vault Secrets Operator Documentation](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)
- [VSO GitHub Repository](https://github.com/hashicorp/vault-secrets-operator)

---

## Предлагаемые изменения

### 1. Новые values параметры

```yaml
# values.yaml

# Текущие (deprecated)
vaultProjectName: ""
vaultNamespace: ""

# Новые (VSO)
vaultSecrets:
  enabled: false
  # Vault auth reference (должен существовать в кластере)
  authRef: "vault-auth"
  # Базовый путь в Vault
  basePath: "secret/data"
  # Проект (часть пути)
  project: "myproject"
  # Окружение (часть пути)
  environment: "dev"
  # Refresh interval
  refreshAfter: "1h"
  # Секреты для синхронизации
  secrets:
    - name: "config"           # Имя VaultStaticSecret
      vaultPath: "config"      # Относительный путь (basePath/project/environment/vaultPath)
      destSecret: "app-config" # Имя создаваемого K8s Secret
      destCreate: true
```

### 2. Новый template: `vault-static-secret.yaml`

```yaml
{{- if .Values.vaultSecrets.enabled }}
{{- range .Values.vaultSecrets.secrets }}
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: {{ .name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "app.labels" $ | nindent 4 }}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
spec:
  type: kv-v2
  mount: {{ $.Values.vaultSecrets.mount | default "secret" }}
  path: {{ $.Values.vaultSecrets.project }}/{{ $.Values.vaultSecrets.environment }}/{{ .vaultPath }}
  destination:
    name: {{ .destSecret }}
    create: {{ .destCreate | default true }}
  refreshAfter: {{ $.Values.vaultSecrets.refreshAfter | default "1h" }}
  vaultAuthRef: {{ $.Values.vaultSecrets.authRef }}
{{- end }}
{{- end }}
```

### 3. Новый template: `vault-auth.yaml` (опционально)

```yaml
{{- if and .Values.vaultSecrets.enabled .Values.vaultSecrets.createAuth }}
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: {{ include "app.fullname" . }}-auth
  namespace: {{ .Release.Namespace }}
spec:
  method: kubernetes
  mount: {{ .Values.vaultSecrets.authMount | default "kubernetes" }}
  kubernetes:
    role: {{ .Values.vaultSecrets.role }}
    serviceAccount: {{ .Values.serviceAccountName | default "app" }}
    audiences:
      - vault
{{- end }}
```

### 4. Обновить deployment.yaml

Добавить ожидание секретов:

```yaml
spec:
  template:
    spec:
      {{- if .Values.vaultSecrets.enabled }}
      initContainers:
        - name: wait-for-secrets
          image: bitnami/kubectl:latest
          command:
            - /bin/sh
            - -c
            - |
              {{- range .Values.vaultSecrets.secrets }}
              until kubectl get secret {{ .destSecret }} -n {{ $.Release.Namespace }}; do
                echo "Waiting for secret {{ .destSecret }}..."
                sleep 2
              done
              {{- end }}
      {{- end }}
```

---

## Пример использования

### values-dev.yaml

```yaml
vaultSecrets:
  enabled: true
  authRef: "vault-auth"
  project: "myapp"
  environment: "dev"
  refreshAfter: "30m"
  secrets:
    - name: db-credentials
      vaultPath: "database"
      destSecret: "myapp-db-secrets"
    - name: api-keys
      vaultPath: "api"
      destSecret: "myapp-api-secrets"
```

### Команда деплоя

```bash
helm upgrade --install myapp k8app/app \
  -f default.yaml \
  -f values-dev.yaml \
  --namespace myapp-dev
```

---

## Миграция с текущего решения

### Шаг 1: Deprecation Notice

В текущем релизе добавить warning:

```yaml
# templates/vault-crd.yaml
{{- if .Values.valult }}
{{- fail "DEPRECATED: 'valult' is deprecated. Please migrate to 'vaultSecrets' with VSO support. See docs/migration-vault.md" }}
{{- end }}
```

### Шаг 2: Документация миграции

Создать `docs/migration-vault.md` с инструкциями:
1. Установка VSO в кластер
2. Создание VaultAuth ресурсов
3. Обновление values файлов
4. Тестирование

### Шаг 3: Удаление legacy

В следующем major релизе удалить:
- `templates/vault-crd.yaml`
- `templates/vault-certs-crd.yaml`
- Параметры `vaultProjectName`, `vaultNamespace`, `valult`

---

## Альтернативы (для рассмотрения)

### External Secrets Operator (ESO)

Если нужна поддержка множества провайдеров (AWS SM, GCP SM, Azure KV):

```yaml
vaultSecrets:
  provider: "vso"  # или "eso"
```

Но для чистого Vault рекомендуется VSO как first-party решение.

---

## Timeline

| Этап | Срок | Описание |
|------|------|----------|
| 1 | v2.x | Добавить VSO support параллельно с legacy |
| 2 | v2.x+1 | Deprecation warning для legacy |
| 3 | v3.0 | Удаление legacy, только VSO |

---

## Контакты

При возникновении вопросов по миграции обращаться к команде Platform Engineering.
