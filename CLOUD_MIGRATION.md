# ☁️ Cloud Migration & Microservices Architecture Guide

This comprehensive document details the system architecture of the E-Commerce Platform, explaining the AWS services utilized in the modular Terraform infrastructure, comparing local vs. production microservices communication, and providing a step-by-step roadmap to migrate from local Docker Compose to the AWS Cloud.

---

## 1. 🛠️ AWS Services Covered in the Project

The Terraform configuration (`/terraform/`) defines a production-grade, highly available, secure, and cost-optimized cloud topology. Below are the core AWS services covered in the codebase:

### Networking & Content Delivery
*   **AWS VPC (Virtual Private Cloud)**: Modular network isolation with public, private (app), and database subnets across 3 Availability Zones (AZs). Includes highly redundant NAT Gateways (HA per-AZ in production, single NAT in dev/staging to save cost).
*   **Amazon Route 53**: Highly resilient DNS management, hosting the zone and mapping domain names (e.g., `api.domain.com`, `argocd.domain.com`) to the Application Load Balancer (ALB).
*   **AWS Certificate Manager (ACM)**: Automates provisioning, renewal, and management of public SSL/TLS certificates for encrypted HTTPS termination at the ALB/CloudFront boundary.
*   **Amazon CloudFront**: Global CDN (Content Delivery Network) caching static assets, optimizing page load times, and verifying customized custom headers to ensure requests only hit the ALB through CloudFront (origin protection).

### Compute & Orchestration
*   **Amazon EKS (Elastic Kubernetes Service) v1.31**: Managed K8s cluster orchestrating the 5 FastAPI microservices. Utilizes optimized EC2 managed node groups:
    *   **Production**: High-availability `ON_DEMAND` instances across 3 AZs.
    *   **Development**: Cost-saving `SPOT` instances with auto-scaling to minimize cloud bills.
*   **Amazon ECR (Elastic Container Registry)**: Private Docker registries for securely versioning, vulnerability scanning (Trivy integration), and hosting microservice container images.

### Databases & Security
*   **Amazon RDS (PostgreSQL 16)**: Production-grade relational database running Multi-AZ replication (standby database in a separate AZ for zero-downtime failover).
*   **AWS WAF v2 (Web Application Firewall)**: Shielding EKS APIs from web attacks (SQL injection, XSS, rate-limiting, and OWASP Top 10 rules).
*   **AWS Shield Standard**: Automated DDoS protection guarding your CloudFront and Route 53 endpoints.
*   **AWS KMS (Key Management Service)**: Handles customer-managed cryptographic keys encrypting RDS disks, EKS secret envelopes, and ECR containers.
*   **AWS IAM & OIDC (OpenID Connect)**: Eliminates static access keys.
    *   **GitHub Actions OIDC**: Assumes short-lived AWS roles using OpenID trust policies.
    *   **EKS IRSA (IAM Roles for Service Accounts)**: Associates dedicated IAM roles directly with K8s pods to query AWS services (e.g., Secrets Manager, S3) securely.
*   **Amazon S3 (Simple Storage Service)**: Houses durable Terraform state files, and serves as the scalable storage backend for Promtail/Loki logging indexes.

---

## 2. 🔌 Microservices Communication Flow

The 5 FastAPI microservices (`user`, `product`, `order`, `payment`, `notification`) are designed with a decoupled share-nothing database architecture. They communicate asynchronously or synchronously using different paradigms locally vs. inside Kubernetes:

```mermaid
graph TD
    subgraph "External Boundary"
        Client[Browser / Client]
        Ingress[API Gateway / ALB]
    end

    subgraph "Microservices Cluster"
        User[User Service]
        Product[Product Service]
        Order[Order Service]
        Payment[Payment Service]
        Notify[Notification Service]
    end

    subgraph "Database Cluster"
        DB_User[(User DB)]
        DB_Prod[(Product DB)]
        DB_Order[(Order DB)]
        DB_Pay[(Payment DB)]
        DB_Notify[(Notification DB)]
    end

    Client -->|HTTPS| Ingress
    Ingress -->|/api/v1/users| User
    Ingress -->|/api/v1/products| Product
    Ingress -->|/api/v1/orders| Order
    Ingress -->|/api/v1/payments| Payment
    Ingress -->|/api/v1/notifications| Notify

    User -.->|HTTP Request| Notify
    Order -.->|HTTP Request| Notify
    Payment -.->|HTTP Request| Notify

    User ===> DB_User
    Product ===> DB_Prod
    Order ===> DB_Order
    Payment ===> DB_Pay
    Notify ===> DB_Notify

    style Ingress fill:#1e293b,stroke:#06b6d4,stroke-width:2px,color:#fff
    style User fill:#3b82f6,stroke:#fff,stroke-width:1px,color:#fff
    style Product fill:#10b981,stroke:#fff,stroke-width:1px,color:#fff
    style Order fill:#8b5cf6,stroke:#fff,stroke-width:1px,color:#fff
    style Payment fill:#06b6d4,stroke:#fff,stroke-width:1px,color:#fff
    style Notify fill:#f59e0b,stroke:#fff,stroke-width:1px,color:#fff
```

### 🐳 A. Local Execution (Docker Compose)
*   **Service Discovery**: Standard container name resolution on an isolated custom network bridge (`project_ecommerce-network`).
*   **DNS Resolution**: Containers locate database endpoints using the service alias `postgres` (e.g. `postgresql://postgres:password@postgres:5432/user_service`).
*   **Service-to-Service Calls**: Microservices call each other directly over the bridge network. For example, during a password reset request, `user-service` resolves `http://notification-service:8000/` inside the network to trigger the email dispatch.
*   **Host Mapping**: Ports are mapped to custom host ports (`8001-8005`, `8081` for UI) to allow you to interact directly with backend docs and UI widgets.

### ☸️ B. Cloud Execution (Kubernetes on EKS)
*   **Service Discovery**: Kubernetes CoreDNS handles internal DNS resolution. Pods contact each other using the K8s service name:
    `http://notification-service.default.svc.cluster.local:8000/`
*   **API Routing (Gateway API)**:
    *   Incoming public traffic lands on the Application Load Balancer (ALB).
    *   The `Gateway` resource provisions the ALB controller.
    *   The `HTTPRoute` resources (defined in `/kubernetes/base/gateway/httproutes/`) inspect URL request paths and forward them to the correct backend `ClusterIP` Services:
        *   Requests for `/api/v1/users/*` are routed to `user-service`.
        *   Requests for `/api/v1/products/*` are routed to `product-service`.
*   **Least-Privilege Networking (NetworkPolicies)**: K8s NetworkPolicies secure the cluster. They restrict cross-pod communication so that only authenticated services (e.g., `user-service`) are allowed to call port `8000` on the `notification-service` pods, preventing lateral movement.
*   **External Secrets Management**: Production pods do not contain environment variables with hardcoded db credentials. Instead, the **External Secrets Operator** connects to **AWS Secrets Manager** using IRSA and maps secure credentials directly into Kubernetes Secrets which FastAPI consumes on startup.

---

## 3. 🚀 Step-by-Step Cloud Migration Roadmap

To transition the microservices from local Docker Compose to your highly secure AWS EKS production cluster, follow this roadmap:

### Phase 1: Infrastructure Provisioning (Terraform)
1.  **Configure AWS CLI**: Ensure your local shell is authenticated with AWS administrator credentials.
2.  **Bootstrap Backend Locking**: Navigate to `/terraform/environments/production` and initialize the S3 state backend. State locking will automatically use native lockfiles via the backend configuration:
    ```bash
    cd terraform/environments/production
    terraform init
    ```
3.  **Deploy Resources**: Run a dry-run plan, review, and apply the infrastructure. This creates your multi-AZ VPC, EKS cluster, private ECR repos, Multi-AZ RDS instance, Route 53 DNS, CloudFront distributions, and IAM OIDC provider roles:
    ```bash
    terraform plan -out=prod.tfplan
    terraform apply prod.tfplan
    ```

### Phase 2: Setup Secrets & Database Configuration
1.  **Configure AWS Secrets**: Create a database secret inside **AWS Secrets Manager** containing your secure PostgreSQL credentials.
2.  **Seed Production RDS Schema**: Connect to the private PostgreSQL database via a secure VPN/Bastion or run a temporary job inside the EKS cluster utilizing the `scripts/init-db.sql` schema to prepare the tables.

### Phase 3: CI/CD & Security Pipelines (GitHub Actions)
1.  **Configure GitHub OIDC Role**: Note the ARN of the IAM OIDC Role generated during the Terraform run.
2.  **Trigger Pipeline**: Push changes to the `main` branch. The DevSecOps pipeline (`.github/workflows/`) runs:
    *   **SAST & SCA Scanning**: (Bandit, Semgrep, Pip-audit).
    *   **Container Build & Trivy Scan**: Builds images, scans for CVEs (failing on criticals).
    *   **Secure Push**: Authenticates with AWS ECR via OIDC and pushes Docker images.
    *   **Image Provenance**: Keyless signs container images using `cosign` and GitHub's OIDC.
    *   **Helm Values Update**: Auto-updates the image tag references in the service's helm charts.

### Phase 4: GitOps Bootstrapping (ArgoCD & Gateway API)
1.  **Configure kubectl**: Associate kubectl with your EKS cluster:
    ```bash
    aws eks update-kubeconfig --name ecommerce-production-eks --region ap-south-1
    ```
2.  **Install Gateway API CRDs & ArgoCD**: Boot platforms services:
    ```bash
    # Apply custom gateway routes
    kubectl apply -f kubernetes/base/
    ```
3.  **Bootstrap ArgoCD App-of-Apps**: Load the ArgoCD application manifest:
    ```bash
    kubectl apply -f argocd/app-of-apps.yaml
    ```
    ArgoCD will automatically discover the repository, sync your Helm Charts (`/services/*/helm`), and deploy your microservice pods, services, network policies, and autoscalers!

---

## 4. 💰 Cloud Cost Optimization & Security Checklist

When deploying to production, verify that you adhere to the cost-control and security features already coded in the platform:

| Core Requirement | AWS Implementation | Folder / File Reference |
| :--- | :--- | :--- |
| **No Stored Keys** | GitHub Actions authentication via AWS OIDC provider | `/.github/workflows/ci-shared-template.yaml` |
| **DDoS origin shield** | ALB origin header verification via CloudFront CDN | `/terraform/modules/cloudfront/` |
| **Zero secrets in Git** | External Secrets Operator mappings with AWS Secrets Manager | `/kubernetes/base/secrets/` |
| **Fail-Safe failover** | Multi-AZ PostgreSQL RDS Instance | `/terraform/modules/rds/` |
| **Low-cost routing** | Single ALB shared by 5 services via Gateway HTTPRoutes | `/kubernetes/base/gateway/` |
| **State locking** | S3 Backend utilizing native lockfiles (`use_lockfile = true`) | `/terraform/environments/*/backend.tf` |
| **Development cost control** | EKS Spot Node Groups for Dev / Staging | `/terraform/environments/dev/main.tf` |
