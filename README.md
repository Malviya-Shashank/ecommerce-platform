# 🛒 E-Commerce Platform - Production Microservices

Production-grade e-commerce platform with 5 microservices running on AWS EKS, managed by Terraform IaC, GitHub Actions CI, and ArgoCD GitOps CD.

## Architecture

```
Internet → Route53 → CloudFront (WAF + Shield) → ALB
  → Gateway API → HTTPRoutes → Microservices

ArgoCD:    argocd.domain.com  → Gateway API → ArgoCD Server (ClusterIP)
Grafana:   grafana.domain.com → Gateway API → Grafana (ClusterIP)
API:       api.domain.com     → Gateway API → 5 Microservices
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Cloud** | AWS (EKS, RDS, CloudFront, WAF, Shield, Route53, ECR) |
| **IaC** | Terraform with modular architecture |
| **Orchestration** | Kubernetes (EKS v1.31) |
| **Package Manager** | Helm 3 |
| **CI** | GitHub Actions (OIDC auth, Trivy scanning) |
| **CD** | ArgoCD (GitOps, App-of-Apps pattern) |
| **Monitoring** | Prometheus + Grafana |
| **Logging** | Loki + Promtail (S3-backed) |
| **API Gateway** | Kubernetes Gateway API |
| **Services** | Python/FastAPI |
| **Database** | PostgreSQL 16 (RDS Multi-AZ) |

## Microservices

| Service | Path | Description |
|---------|------|-------------|
| user-service | `/api/v1/users` | Registration, auth, profiles |
| product-service | `/api/v1/products` | Catalog, inventory, search |
| order-service | `/api/v1/orders` | Cart, checkout, orders |
| payment-service | `/api/v1/payments` | Payment processing, refunds |
| notification-service | `/api/v1/notifications` | Email, SMS, push |

## Project Structure

```
├── terraform/                  # Infrastructure as Code
│   ├── modules/                # Reusable Terraform modules
│   │   ├── vpc/                # VPC, subnets, NAT
│   │   ├── eks/                # EKS cluster, node groups
│   │   ├── rds/                # PostgreSQL Multi-AZ
│   │   ├── route53/            # DNS
│   │   ├── cloudfront/         # CDN + origin protection
│   │   ├── waf/                # WAF v2 rules
│   │   ├── shield/             # DDoS protection
│   │   ├── acm/                # TLS certificates
│   │   ├── irsa/               # IAM Roles for Service Accounts
│   │   ├── security-groups/    # Network security
│   │   └── helm-releases/      # Platform services via Helm
│   └── environments/           # Per-environment configs
│       ├── dev/
│       ├── staging/
│       └── production/
├── services/                   # Microservice source code
│   ├── user-service/
│   ├── product-service/
│   ├── order-service/
│   ├── payment-service/
│   └── notification-service/
├── kubernetes/                 # K8s manifests (Gateway API)
├── argocd/                     # ArgoCD application manifests
├── .github/workflows/          # CI pipelines
└── scripts/                    # Setup/teardown scripts
```

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.9.0
- kubectl
- Helm 3
- Docker

### 1. Setup Backend
```bash
chmod +x scripts/setup.sh
./scripts/setup.sh ecommerce ap-south-1
```

### 2. Configure
```bash
cd terraform/environments/production
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply
```

### 4. Configure kubectl
```bash
aws eks update-kubeconfig --name ecommerce-production-eks --region ap-south-1
```

### 5. Apply Gateway API Routes
```bash
kubectl apply -f kubernetes/base/
```

### 6. Bootstrap ArgoCD
```bash
kubectl apply -f argocd/projects/
kubectl apply -f argocd/app-of-apps.yaml
```

## Environments

| Environment | VPC CIDR | Nodes | RDS | NAT |
|------------|----------|-------|-----|-----|
| dev | 10.1.0.0/16 | 2× SPOT m6i.large | Single-AZ t4g.medium | Single |
| staging | 10.2.0.0/16 | 2× ON_DEMAND m6i.large | Multi-AZ t4g.large | Single |
| production | 10.0.0.0/16 | 3× ON_DEMAND m6i.xlarge | Multi-AZ r6g.large | HA (per AZ) |

## Cost Optimization

- ✅ **Single ALB** shared via Gateway API (saves ~$36/month vs 3 separate LBs)
- ✅ **ArgoCD & Grafana** via ClusterIP + HTTPRoute (no extra NLBs)
- ✅ **Loki S3 storage** with lifecycle (Standard → IA → Glacier)
- ✅ **VPC endpoints** for ECR/STS (reduces NAT traffic costs)
- ✅ **SPOT instances** for dev environment
- ✅ **Shield Advanced** opt-in only (default: standard)

## Security

- 🔐 KMS encryption for EKS secrets and RDS
- 🔐 IRSA (no AWS credentials in pods)
- 🔐 WAF with OWASP, SQLi, rate limiting rules
- 🔐 CloudFront origin header validation
- 🔐 Network policies per service
- 🔐 GitHub OIDC (no long-lived IAM keys)
- 🔐 External Secrets Operator (no secrets in Git)
- 🔐 Non-root containers with read-only filesystem
