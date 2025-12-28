# Talos Machine Configuration Patches

Этот каталог содержит YAML-патчи для настройки Talos Linux.

## Как работают патчи

Talos использует [strategic merge patch](https://www.talos.dev/v1.9/talos-guides/configuration/patching/)
для кастомизации machine configuration. Патчи применяются поверх базовой конфигурации.

## Структура

```
shared/talos/
├── README.md
└── patches/
    ├── common.yaml       # Общие патчи для всех платформ
    ├── docker.yaml       # Docker Desktop специфичные (local dev)
    ├── bare-metal.yaml   # Bare-metal homelab специфичные
    ├── hetzner.yaml      # Hetzner Cloud специфичные
    └── homelab.yaml      # Homelab специфичные
```

## Использование

### Docker (local development)

```bash
talosctl cluster create \
  --name talos-local \
  --config-patch @shared/talos/patches/docker.yaml
```

### Bare-metal

```bash
talosctl gen config my-cluster https://VIP:6443 \
  --config-patch @shared/talos/patches/common.yaml \
  --config-patch @shared/talos/patches/bare-metal.yaml \
  --output-dir ./talos-configs
```

## Базовые патчи

Все платформы используют следующие настройки:

```yaml
# Отключить встроенный CNI (используем Cilium)
cluster:
  network:
    cni:
      name: none
  # Отключить kube-proxy (Cilium его заменяет)
  proxy:
    disabled: true
```

## Примеры патчей

### Добавить system extension

```yaml
# patches/extensions.yaml
machine:
  install:
    extensions:
      - image: ghcr.io/siderolabs/qemu-guest-agent:0.1.0
      - image: ghcr.io/siderolabs/iscsi-tools:v0.1.4
```

### Настроить DNS

```yaml
# patches/dns.yaml
machine:
  network:
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
```

### Настроить NTP

```yaml
# patches/ntp.yaml
machine:
  time:
    servers:
      - time.cloudflare.com
```

### Настроить Kubelet

```yaml
# patches/kubelet.yaml
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: "true"
    nodeIP:
      validSubnets:
        - 10.0.0.0/8
```

### VIP для HA

```yaml
# patches/vip.yaml
machine:
  network:
    interfaces:
      - interface: eth0
        dhcp: true
        vip:
          ip: 192.168.1.100  # Shared VIP
```

## Валидация патчей

```bash
# Валидировать patch файл
talosctl validate -m patch -c patches/bare-metal.yaml

# Сгенерировать конфигурацию с патчем и проверить
talosctl gen config my-cluster https://api.example.com:6443 \
  --config-patch @patches/bare-metal.yaml \
  --output-types controlplane \
  --output /dev/stdout | talosctl validate -m dryrun
```

## Ссылки

- [Talos Configuration Patching](https://www.talos.dev/v1.9/talos-guides/configuration/patching/)
- [Talos Machine Configuration](https://www.talos.dev/v1.9/reference/configuration/)
- [System Extensions](https://www.talos.dev/v1.9/talos-guides/configuration/system-extensions/)
