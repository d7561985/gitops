# GitOps POC - Development helpers

.PHONY: help proxy-vault proxy-argocd proxy-all proxy-api-gateway proxy-grafana proxy-prometheus stop-proxy hubble-ui

help:
	@echo "Available commands:"
	@echo ""
	@echo "Proxy commands:"
	@echo "  make proxy-vault       - Port-forward Vault UI (8200)"
	@echo "  make proxy-argocd      - Port-forward ArgoCD UI (8081)"
	@echo "  make proxy-api-gateway - Port-forward API Gateway (8080, 8000)"
	@echo "  make proxy-grafana     - Port-forward Grafana UI (3000)"
	@echo "  make proxy-prometheus  - Port-forward Prometheus UI (9090)"
	@echo "  make proxy-all         - Start all proxies"
	@echo "  make stop-proxy        - Stop all port-forwards"
	@echo ""
	@echo "Observability commands:"
	@echo "  make hubble-ui         - Open Hubble UI (network flows)"
	@echo "  make hubble-observe    - Watch network flows in terminal"

proxy-vault:
	@echo "============================================"
	@echo "Starting Vault UI proxy..."
	@echo "============================================"
	@echo ""
	@echo "URL:   http://127.0.0.1:8200"
	@echo -n "Token: "
	@kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d && echo "" || echo "root (dev mode)"
	@echo ""
	@echo "Press Ctrl+C to stop"
	@echo "============================================"
	@kubectl port-forward -n vault svc/vault-ui 8200:8200

proxy-argocd:
	@echo "============================================"
	@echo "Starting ArgoCD UI proxy..."
	@echo "============================================"
	@echo ""
	@echo "URL:      http://127.0.0.1:8081"
	@echo "User:     admin"
	@echo -n "Password: "
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo ""
	@echo ""
	@echo "Press Ctrl+C to stop"
	@echo "============================================"
	@kubectl port-forward -n argocd svc/argocd-server 8081:80

proxy-api-gateway:
	@echo "============================================"
	@echo "Starting API Gateway proxy..."
	@echo "============================================"
	@echo ""
	@echo "API:   http://127.0.0.1:8080/api/"
	@echo "Admin: http://127.0.0.1:8000"
	@echo ""
	@echo "Test commands:"
	@echo "  curl http://127.0.0.1:8000/ready"
	@echo "  curl http://127.0.0.1:8080/api/HttpService/health"
	@echo ""
	@echo "Press Ctrl+C to stop"
	@echo "============================================"
	@kubectl port-forward -n poc-dev svc/api-gateway-sv 8080:8080 8000:8000

proxy-all:
	@echo "============================================"
	@echo "Starting all proxies in background..."
	@echo "============================================"
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@sleep 1
	@kubectl port-forward -n vault svc/vault-ui 8200:8200 &
	@kubectl port-forward -n argocd svc/argocd-server 8081:80 &
	@kubectl port-forward -n poc-dev svc/api-gateway-sv 8080:8080 8000:8000 2>/dev/null &
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 2>/dev/null &
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 2>/dev/null &
	@sleep 2
	@echo ""
	@echo -n "Vault UI:    http://127.0.0.1:8200  (Token: "
	@kubectl get secret vault-keys -n vault -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || echo -n "root"
	@echo ")"
	@echo ""
	@echo "ArgoCD UI:   http://127.0.0.1:8081"
	@echo "  User:      admin"
	@echo -n "  Password:  "
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo ""
	@echo ""
	@echo "API Gateway: http://127.0.0.1:8080/api/"
	@echo "  Admin:     http://127.0.0.1:8000"
	@echo ""
	@echo "Grafana:     http://127.0.0.1:3000  (admin / admin)"
	@echo "Prometheus:  http://127.0.0.1:9090"
	@echo ""
	@echo "Hubble UI:   run 'make hubble-ui'"
	@echo ""
	@echo "Run 'make stop-proxy' to stop all proxies"
	@echo "============================================"

stop-proxy:
	@echo "Stopping all port-forwards..."
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@echo "Done"

# =============================================================================
# Monitoring proxies
# =============================================================================

proxy-grafana:
	@echo "============================================"
	@echo "Starting Grafana UI proxy..."
	@echo "============================================"
	@echo ""
	@echo "URL:      http://127.0.0.1:3000"
	@echo "User:     admin"
	@echo -n "Password: "
	@kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d && echo "" || echo "admin"
	@echo ""
	@echo "Pre-installed dashboards:"
	@echo "  - Kubernetes Cluster Overview"
	@echo "  - Node Exporter"
	@echo "  - Pod/Deployment metrics"
	@echo ""
	@echo "Cilium dashboards to import:"
	@echo "  - 13286 (Cilium Agent)"
	@echo "  - 13502 (Hubble)"
	@echo ""
	@echo "Press Ctrl+C to stop"
	@echo "============================================"
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

proxy-prometheus:
	@echo "============================================"
	@echo "Starting Prometheus UI proxy..."
	@echo "============================================"
	@echo ""
	@echo "URL: http://127.0.0.1:9090"
	@echo ""
	@echo "Useful queries:"
	@echo "  - up                              # All targets"
	@echo "  - kubelet_running_pods            # Pod count"
	@echo "  - container_memory_usage_bytes    # Memory usage"
	@echo ""
	@echo "Press Ctrl+C to stop"
	@echo "============================================"
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# =============================================================================
# Hubble (Cilium eBPF observability)
# =============================================================================

hubble-ui:
	@echo "============================================"
	@echo "Opening Hubble UI..."
	@echo "============================================"
	@echo ""
	@echo "Hubble provides:"
	@echo "  - Service dependency maps"
	@echo "  - Network flows (L3/L4/L7)"
	@echo "  - DNS/HTTP visibility"
	@echo "  - Network policy audit"
	@echo ""
	@cilium hubble ui

hubble-observe:
	@echo "============================================"
	@echo "Watching network flows..."
	@echo "============================================"
	@echo ""
	@echo "Press Ctrl+C to stop"
	@echo ""
	@hubble observe --follow
