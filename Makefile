# GitOps POC - Development helpers

.PHONY: help proxy-vault proxy-argocd proxy-all proxy-api-gateway stop-proxy

help:
	@echo "Available commands:"
	@echo "  make proxy-vault       - Port-forward Vault UI (8200)"
	@echo "  make proxy-argocd      - Port-forward ArgoCD UI (8081)"
	@echo "  make proxy-api-gateway - Port-forward API Gateway (8080, 8000)"
	@echo "  make proxy-all         - Start all proxies"
	@echo "  make stop-proxy        - Stop all port-forwards"

proxy-vault:
	@echo "============================================"
	@echo "Starting Vault UI proxy..."
	@echo "============================================"
	@echo ""
	@echo "URL:   http://127.0.0.1:8200"
	@echo "Token: root"
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
	@kubectl port-forward -n poc-dev svc/api-gateway-sv 8080:8080 8000:8000 &
	@sleep 2
	@echo ""
	@echo "Vault UI:    http://127.0.0.1:8200  (Token: root)"
	@echo ""
	@echo "ArgoCD UI:   http://127.0.0.1:8081"
	@echo "  User:      admin"
	@echo -n "  Password:  "
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo ""
	@echo ""
	@echo "API Gateway: http://127.0.0.1:8080/api/"
	@echo "  Admin:     http://127.0.0.1:8000"
	@echo ""
	@echo "Run 'make stop-proxy' to stop all proxies"
	@echo "============================================"

stop-proxy:
	@echo "Stopping all port-forwards..."
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@echo "Done"
