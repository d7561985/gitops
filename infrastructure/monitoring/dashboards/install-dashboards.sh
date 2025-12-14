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
create_dashboard_configmap "${JSON_DIR}/redis-exporter.json" "redis-dashboard" "Infrastructure"
create_dashboard_configmap "${JSON_DIR}/rabbitmq-monitoring.json" "rabbitmq-dashboard" "Infrastructure"
create_dashboard_configmap "${JSON_DIR}/mongodb.json" "mongodb-dashboard" "Infrastructure"
create_dashboard_configmap "${JSON_DIR}/envoy-global.json" "envoy-dashboard" "Infrastructure"

echo ""
echo "Dashboards installed successfully!"
echo ""
echo "Verify with: kubectl get configmaps -n ${NAMESPACE} -l grafana_dashboard=1"
echo ""
echo "NOTE: Grafana sidecar will auto-reload dashboards within ~60 seconds"
