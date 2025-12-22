#!/bin/bash
# Install Grafana dashboards as ConfigMaps
# Dashboards with label grafana_dashboard=1 are auto-loaded by Grafana sidecar

set -e

NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_DIR="${SCRIPT_DIR}/json"

echo "Installing Grafana dashboards to namespace: ${NAMESPACE}"

# Function to create ConfigMap from dashboard JSON
create_dashboard_configmap() {
    local json_file="$1"
    local name="$2"
    local folder="$3"

    if [[ ! -f "${json_file}" ]]; then
        echo "ERROR: File not found: ${json_file}"
        return 1
    fi

    echo "Creating ConfigMap: ${name} (folder: ${folder})"

    kubectl create configmap "${name}" \
        --from-file="${name}.json=${json_file}" \
        --namespace="${NAMESPACE}" \
        --dry-run=client -o yaml | \
    kubectl label --local -f - \
        grafana_dashboard=1 \
        --dry-run=client -o yaml | \
    kubectl annotate --local -f - \
        grafana_folder="${folder}" \
        --dry-run=client -o yaml | \
    kubectl apply -f -
}

# Install dashboards
# Redis
create_dashboard_configmap "${JSON_DIR}/redis-exporter.json" "redis-dashboard" "Infrastructure"

# RabbitMQ - Official dashboard from RabbitMQ team (for rabbitmq_prometheus plugin)
# Source: https://github.com/rabbitmq/rabbitmq-server/tree/main/deps/rabbitmq_prometheus/docker/grafana/dashboards
create_dashboard_configmap "${JSON_DIR}/rabbitmq-overview-official.json" "rabbitmq-overview-dashboard" "Infrastructure"

# MongoDB - Dashboard 12079: compatible with percona/mongodb_exporter
# Source: https://grafana.com/grafana/dashboards/12079
create_dashboard_configmap "${JSON_DIR}/mongodb-percona-compat.json" "mongodb-percona-dashboard" "Infrastructure"

# Envoy - Global overview
create_dashboard_configmap "${JSON_DIR}/envoy-global.json" "envoy-dashboard" "Infrastructure"

# Envoy - Clusters detail
# Source: https://grafana.com/grafana/dashboards/11021
create_dashboard_configmap "${JSON_DIR}/envoy-clusters.json" "envoy-clusters-dashboard" "Infrastructure"

# Service Golden Signals - Universal dashboard for services using Hubble eBPF metrics
# Shows 4 Golden Signals: Latency, Traffic, Errors, Saturation
# Based on: https://grafana.com/grafana/dashboards/21073 + Hubble HTTP metrics
create_dashboard_configmap "${JSON_DIR}/service-golden-signals.json" "service-golden-signals-dashboard" "Services"

echo ""
echo "Dashboards installed successfully!"
echo ""
echo "Verify with: kubectl get configmaps -n ${NAMESPACE} -l grafana_dashboard=1"
echo ""
echo "NOTE: Grafana sidecar will auto-reload dashboards within ~60 seconds"
