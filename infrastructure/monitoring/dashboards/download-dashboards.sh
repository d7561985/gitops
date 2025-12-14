#!/bin/bash
# =============================================================================
# Download Grafana Dashboards
# =============================================================================
# Downloads popular community dashboards from grafana.com
# Dashboards are saved as JSON files for ConfigMap creation
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Downloading Grafana dashboards..."

# Function to download dashboard from grafana.com
download_dashboard() {
    local id=$1
    local name=$2
    local revision=${3:-1}

    echo "  Downloading: $name (ID: $id, revision: $revision)"

    # Get the dashboard JSON using grafana.com API
    curl -s "https://grafana.com/api/dashboards/${id}/revisions/${revision}/download" \
        -o "${SCRIPT_DIR}/${name}.json"

    if [ -s "${SCRIPT_DIR}/${name}.json" ]; then
        echo "    OK: ${name}.json"
    else
        echo "    FAILED: ${name}.json"
        rm -f "${SCRIPT_DIR}/${name}.json"
    fi
}

# =============================================================================
# Cilium / Hubble Dashboards
# =============================================================================
echo ""
echo "Cilium & Hubble dashboards:"
download_dashboard 13286 "cilium-agent" 1
download_dashboard 13502 "hubble" 1
download_dashboard 13537 "hubble-dns" 1
download_dashboard 13538 "hubble-http" 1

# =============================================================================
# MongoDB Dashboard
# =============================================================================
echo ""
echo "MongoDB dashboards:"
download_dashboard 2583 "mongodb" 1
download_dashboard 14997 "mongodb-exporter" 1

# =============================================================================
# RabbitMQ Dashboard
# =============================================================================
echo ""
echo "RabbitMQ dashboards:"
download_dashboard 10991 "rabbitmq" 11
download_dashboard 4279 "rabbitmq-overview" 4

# =============================================================================
# Redis Dashboard
# =============================================================================
echo ""
echo "Redis dashboards:"
download_dashboard 11835 "redis" 1
download_dashboard 763 "redis-dashboard" 6

# =============================================================================
# Node Exporter (already included in kube-prometheus-stack but good to have)
# =============================================================================
echo ""
echo "Node Exporter dashboards:"
download_dashboard 1860 "node-exporter-full" 37

echo ""
echo "Done! Dashboards saved to: ${SCRIPT_DIR}"
echo ""
echo "To apply dashboards to Grafana, run:"
echo "  kubectl apply -f monitoring/dashboards/configmaps/"
echo ""
