# 🖥️ CLI Deployment & Testing Guide (Local & Cloud)

This guide provides the exact terminal commands required to launch, monitor, test, and troubleshoot the e-commerce microservices platform in both your local environment (Docker Compose) and the AWS Cloud (EKS/Terraform).

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

Run these `curl` commands to confirm the network gateway and databases are active:

```bash
# 🖥️ Frontend Web Portal (Nginx static web server)
curl -I http://localhost:8081

# 👤 User Service (Port 8001)
curl -s http://localhost:8001/healthz
curl -s http://localhost:8001/readyz

# 🛍️ Product Catalog (Port 8002)
curl -s http://localhost:8002/healthz
curl -s http://localhost:8002/readyz

# 📦 Order Service (Port 8003)
curl -s http://localhost:8003/healthz
curl -s http://localhost:8003/readyz

# 💳 Payment Service (Port 8004)
curl -s http://localhost:8004/healthz
curl -s http://localhost:8004/readyz

# 🔔 Notification Service (Port 8005)
curl -s http://localhost:8005/healthz
curl -s http://localhost:8005/readyz
```

---

### C. Direct Backend API Testing (CLI Mocking)

#### 1. Real User Authentication (Login)
Sends credentials to `user-service` to verify password hashing (using the seeded developer account):
```bash
curl -s -X POST http://localhost:8001/login \
  -H "Content-Type: application/json" \
  -d '{"username_or_email": "alex_dev", "password": "securepassword123"}'
```

#### 2. Create User Account (Registration)
Registers a new customer. The user-service hashes the password before storing:
```bash
curl -s -X POST http://localhost:8001/ \
  -H "Content-Type: application/json" \
  -d '{"email": "test.user@example.com", "username": "test_user", "full_name": "Test User", "password": "mypassword456"}'
```

#### 3. Real Password Reset Flow
Generates a token and triggers microservice-to-microservice network integration:
```bash
curl -s -X POST http://localhost:8001/forgot-password \
  -H "Content-Type: application/json" \
  -d '{"email": "sarah.manager@example.com"}'
```

#### 4. Fetch Sent Notification Alerts
Verify the password reset instruction or purchase receipt email was queued inside the `notification-service`:
```bash
curl -s http://localhost:8005/user/2
```

#### 5. Submit an Order
Create a new order for a catalog laptop (Product ID `1`):
```bash
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

### A. Infrastructure Provisioning (IaC)

Navigate to the target environment directory (e.g. `production` or `dev`):

```bash
cd terraform/environments/production
```

#### 1. Initialize S3 Backend
Initializes lockfile state configuration (wiping the DynamoDB state locks requirement):
```bash
terraform init
```

#### 2. Dry Run Plan Verification
Generates an audit trail of infrastructure changes:
```bash
terraform plan -out=tfplan.binary
```

#### 3. Apply Production Infrastructure
```bash
terraform apply tfplan.binary
```

---

### B. EKS Cluster Operations & GitOps Bootstrapping

#### 1. Update Kubeconfig
Connect local `kubectl` to EKS:
```bash
aws eks update-kubeconfig --name ecommerce-production-eks --region ap-south-1
```

#### 2. Apply Kubernetes Gateway API Routing Manifests
```bash
kubectl apply -f kubernetes/base/
```

#### 3. Deploy Platform via GitOps App-of-Apps
```bash
kubectl apply -f argocd/app-of-apps.yaml
```

---

### C. Kubernetes Diagnostic Commands

#### Check Pod Status (All namespaces)
```bash
kubectl get pods -A
```

#### Check EKS Gateway APIs Routing Config
```bash
kubectl get gateways,httproutes -n default
```

#### Inspect Live Container Logs (EKS E-commerce app)
```bash
kubectl logs -l app=user-service -n default --tail=100 -f
```

#### Inspect AWS External Secrets Configuration
```bash
kubectl get externalsecrets,secretstore -n default
```

#### Force ArgoCD Sync (via kubectl)
```bash
kubectl patch application app-of-apps -n argocd --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'
```
