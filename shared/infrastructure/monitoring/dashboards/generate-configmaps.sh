#!/bin/bash
# =============================================================================
# Generate Grafana Dashboard ConfigMaps
# =============================================================================
# Creates Kubernetes ConfigMaps from JSON dashboard files
# ConfigMaps are labeled for automatic discovery by Grafana sidecar
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/configmaps"

mkdir -p "$OUTPUT_DIR"

echo "Generating Grafana Dashboard ConfigMaps..."
echo ""

# Function to generate ConfigMap from JSON file
generate_configmap() {
    local json_file=$1
    local folder=$2
    local name=$(basename "$json_file" .json)

    if [ ! -f "$json_file" ]; then
        echo "  Skipping: $json_file (not found)"
        return
    fi

    local cm_name="grafana-dashboard-${name}"
    local output_file="${OUTPUT_DIR}/${name}-dashboard.yaml"

    echo "  Generating: $cm_name (folder: $folder)"

    cat > "$output_file" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${cm_name}
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: "${folder}"
data:
  ${name}.json: |
EOF

    # Indent JSON content by 4 spaces
    sed 's/^/    /' "$json_file" >> "$output_file"

    echo "    Created: $output_file"
}

# =============================================================================
# Generate ConfigMaps by category
# =============================================================================

echo "Cilium & Hubble dashboards:"
generate_configmap "${SCRIPT_DIR}/cilium-agent.json" "Cilium"
generate_configmap "${SCRIPT_DIR}/hubble.json" "Cilium"
generate_configmap "${SCRIPT_DIR}/hubble-dns.json" "Cilium"
generate_configmap "${SCRIPT_DIR}/hubble-http.json" "Cilium"

echo ""
echo "MongoDB dashboards:"
generate_configmap "${SCRIPT_DIR}/mongodb.json" "Infrastructure"
generate_configmap "${SCRIPT_DIR}/mongodb-exporter.json" "Infrastructure"

echo ""
echo "RabbitMQ dashboards:"
generate_configmap "${SCRIPT_DIR}/rabbitmq.json" "Infrastructure"
generate_configmap "${SCRIPT_DIR}/rabbitmq-overview.json" "Infrastructure"

echo ""
echo "Redis dashboards:"
generate_configmap "${SCRIPT_DIR}/redis.json" "Infrastructure"
generate_configmap "${SCRIPT_DIR}/redis-dashboard.json" "Infrastructure"

echo ""
echo "Node Exporter dashboards:"
generate_configmap "${SCRIPT_DIR}/node-exporter-full.json" "Nodes"

# =============================================================================
# Generate kustomization.yaml
# =============================================================================

echo ""
echo "Generating kustomization.yaml..."

cat > "${OUTPUT_DIR}/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
EOF

# Add all generated ConfigMaps
for f in "${OUTPUT_DIR}"/*-dashboard.yaml; do
    if [ -f "$f" ]; then
        echo "  - $(basename $f)" >> "${OUTPUT_DIR}/kustomization.yaml"
    fi
done

echo ""
echo "Done!"
echo ""
echo "Generated files in: ${OUTPUT_DIR}"
echo ""
echo "To apply dashboards:"
echo "  kubectl apply -k ${OUTPUT_DIR}"
echo ""
echo "Or add to ArgoCD Application for GitOps management."
echo ""
