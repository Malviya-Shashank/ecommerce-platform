# 🖥️ CLI Deployment & Testing Guide (Local & Cloud)

This guide provides the exact terminal commands required to launch, monitor, test, and troubleshoot the e-commerce microservices platform in both your local environment (Docker Compose) and the AWS Cloud (EKS/Terraform).

> **Note:** Cloud infrastructure deployment is fully automated via GitHub Actions. The commands below are for **local development**, **debugging**, and **manual overrides** only.

---

## 🐳 1. Local Environment (Docker Compose)

### A. Operations & Control Commands

#### Spin Up Clean Stack (Builds images & wipes old DB volumes to re-seed)
```bash
docker compose down -v && docker compose up -d --build
```

#### Check Container Running Status
```bash
docker compose ps
```

#### Monitor Live Logs (All services)
```bash
docker compose logs -f
```

#### Monitor Live Logs (Single service)
```bash
docker compose logs -f user-service
```

#### Tear Down Stack (Saves data volumes)
```bash
docker compose down
```

#### Tear Down Stack (Wipes all data volumes)
```bash
docker compose down -v
```

---

### B. Health & Readiness Verification

```bash
# 🖥️ Frontend Web Portal (Nginx static web server)
curl -I http://localhost:8081

# 👤 User Service (HTTP: 8001)
curl -s http://localhost:8001/healthz
curl -s http://localhost:8001/readyz

# 🛍️ Product Catalog (HTTP: 8002, gRPC: 50052)
curl -s http://localhost:8002/healthz
curl -s http://localhost:8002/readyz

# 📦 Order Service (HTTP: 8003)
curl -s http://localhost:8003/healthz
curl -s http://localhost:8003/readyz

# 💳 Payment Service (HTTP: 8004)
curl -s http://localhost:8004/healthz
curl -s http://localhost:8004/readyz

# 🔔 Notification Service (HTTP: 8005, gRPC: 50051)
curl -s http://localhost:8005/healthz
curl -s http://localhost:8005/readyz
```

---

### C. gRPC Testing (Local)

#### Install grpcurl (if not installed)
```bash
brew install grpcurl  # macOS
```

#### List gRPC services (notification-service)
```bash
grpcurl -plaintext localhost:50051 list
```

#### List gRPC services (product-service)
```bash
grpcurl -plaintext localhost:50052 list
```

#### Test notification via gRPC
```bash
grpcurl -plaintext -d '{
  "user_id": 1,
  "type": "email",
  "subject": "Test Notification",
  "message": "Hello from gRPC!"
}' localhost:50051 ecommerce.notification.NotificationService/SendNotification
```

#### Test stock check via gRPC
```bash
grpcurl -plaintext -d '{
  "product_id": 1,
  "requested_quantity": 2
}' localhost:50052 ecommerce.product.ProductService/CheckStock
```

---

### D. Direct Backend API Testing (REST)

#### 1. Real User Authentication (Login)
```bash
curl -s -X POST http://localhost:8001/login \
  -H "Content-Type: application/json" \
  -d '{"username_or_email": "alex_dev", "password": "securepassword123"}'
```

#### 2. Create User Account (Registration)
```bash
curl -s -X POST http://localhost:8001/ \
  -H "Content-Type: application/json" \
  -d '{"email": "test.user@example.com", "username": "test_user", "full_name": "Test User", "password": "mypassword456"}'
```

#### 3. Password Reset (Triggers gRPC notification)
```bash
# This triggers user-service → notification-service gRPC call
curl -s -X POST http://localhost:8001/forgot-password \
  -H "Content-Type: application/json" \
  -d '{"email": "sarah.manager@example.com"}'
```

#### 4. Verify Notification Was Sent (via gRPC)
```bash
curl -s http://localhost:8005/user/2
```

#### 5. Submit an Order (Triggers gRPC stock check + notification)
```bash
# This triggers:
#   1. order-service → product-service gRPC CheckStock
#   2. order-service → notification-service gRPC SendNotification
curl -s -X POST http://localhost:8003/ \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 1,
    "items": [
      {"product_id": 1, "quantity": 1, "price": 1899.99}
    ],
    "shipping_address": {
      "street": "100 Terminal Drive",
      "city": "Silicon Valley",
      "country": "USA"
    }
  }'
```

---
---

## ☁️ 2. Cloud Environment (AWS EKS & Terraform)

### 🤖 A. Automated Deployment (GitHub Actions — Primary Method)

> **Infrastructure and applications are deployed automatically on every push to `main`.**

```mermaid
flowchart LR
    Push["git push main"] --> TF["Terraform Apply"] --> Helm["Helm Charts"] --> Argo["ArgoCD Sync"]
    style Push fill:#3b82f6,stroke:#fff,color:#fff
    style Argo fill:#8b5cf6,stroke:#fff,color:#fff
```

**To trigger a deployment, simply push:**
```bash
git push origin main
```

---

### 🔧 B. Manual Override (One-Time Setup or Debugging)

#### 1. Create Terraform State Backend (One-Time)
```bash
chmod +x scripts/setup.sh
./scripts/setup.sh ecommerce ap-south-1
```

#### 2. Manual Terraform Apply (if needed)
```bash
cd terraform/environments/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

#### 3. Configure sslip.io + TLS (After Terraform Apply)
```bash
# Updates kubeconfig, patches Gateway with ACM cert, prints URLs
./scripts/setup-sslip-domain.sh
```

#### 4. Update Kubeconfig (for local kubectl access)
```bash
aws eks update-kubeconfig --name ecommerce-dev-eks --region ap-south-1
```

---

### C. Kubernetes Diagnostic Commands

#### Check Pod Status (All namespaces)
```bash
kubectl get pods -A
```

#### Check Platform Services
```bash
kubectl get pods -n argocd                # ArgoCD
kubectl get pods -n monitoring            # Prometheus, Grafana, Loki
kubectl get pods -n ecommerce             # Application Pods
kubectl get pods -n kube-system           # ALB Controller, Metrics Server
kubectl get pods -n cert-manager          # Cert Manager
kubectl get pods -n external-secrets      # External Secrets Operator
```

#### Check Gateway & Routes
```bash
kubectl get gateways,httproutes -A
```

#### Check TLS Certificate
```bash
# Verify ACM cert is attached to ALB
kubectl describe gateway ecommerce-gateway -n ecommerce | grep certificate
terraform -chdir=terraform/environments/dev output acm_certificate_arn
```

#### Check gRPC Services (via port-forward)
```bash
# Notification service gRPC
kubectl port-forward svc/notification-service 50051:50051 -n ecommerce
grpcurl -plaintext localhost:50051 list

# Product service gRPC
kubectl port-forward svc/product-service 50052:50051 -n ecommerce
grpcurl -plaintext localhost:50052 list
```

#### Check ArgoCD Application Sync Status
```bash
kubectl get applications -n argocd
```

#### Inspect Live Container Logs
```bash
kubectl logs -l app=user-service -n ecommerce --tail=100 -f
```

#### Force ArgoCD Sync (via kubectl)
```bash
kubectl patch application app-of-apps -n argocd --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'
```

---

### D. Proto & gRPC Development

#### Regenerate gRPC Python Stubs (after changing .proto files)
```bash
cd services/proto
bash gen_proto.sh
```

#### Verify Generated Stubs
```bash
for svc in user-service product-service order-service payment-service notification-service; do
  echo "=== $svc ==="
  ls -la services/$svc/src/generated/
done
```
