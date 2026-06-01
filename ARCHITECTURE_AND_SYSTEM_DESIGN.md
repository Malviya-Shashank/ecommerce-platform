# 📐 E-Commerce Platform - System Design & Architecture Spec

This specification document outlines the system design, microservice patterns, perimeter routing security, data isolation strategies, and scalability boundaries of the E-Commerce Microservices Platform.

---

## 1. 🏗️ High-Level System Architecture

The platform follows a modern cloud-native architecture, incorporating **Security-at-Perimeter**, **Stateless Compute**, **gRPC Inter-Service Communication**, and **Database-per-Microservice** design patterns.

```mermaid
graph TD
    subgraph "External Security Perimeter (AWS Edge)"
        DNS["Route 53 DNS<br/>(prod) / sslip.io (dev)"]
        CDN["CloudFront CDN<br/>(prod only)"]
        WAF["WAF v2 & Shield Standard"]
        TLS["TLS Termination<br/>ACM Certificate"]
        ALB["Application Load Balancer<br/>HTTPS :443 + HTTP→HTTPS redirect"]
    end

    subgraph "Kubernetes Gateway API Boundary (EKS Cluster)"
        GW["K8s Gateway Controller"]
        RouteU["HTTPRoute: /api/v1/users"]
        RouteP["HTTPRoute: /api/v1/products"]
        RouteO["HTTPRoute: /api/v1/orders"]
        RoutePay["HTTPRoute: /api/v1/payments"]
        RouteN["HTTPRoute: /api/v1/notifications"]
        RouteArgo["HTTPRoute: /argocd"]
        RouteGraf["HTTPRoute: /grafana"]
    end

    subgraph "Compute Layer (Stateless Microservices)"
        User["User Service<br/>:8000 HTTP"]
        Product["Product Service<br/>:8000 HTTP | :50051 gRPC"]
        Order["Order Service<br/>:8000 HTTP"]
        Payment["Payment Service<br/>:8000 HTTP"]
        Notify["Notification Service<br/>:8000 HTTP | :50051 gRPC"]
    end

    subgraph "Data Persistence Layer (RDS PostgreSQL)"
        DB_User[("User DB")]
        DB_Prod[("Product DB")]
        DB_Order[("Order DB")]
        DB_Pay[("Payment DB")]
        DB_Notify[("Notification DB")]
    end

    %% External Connections
    UserSystem["Client Browser"] -->|"HTTPS Requests"| DNS
    DNS --> CDN
    CDN -->|"Verify Header & TLS"| WAF
    WAF --> TLS
    TLS --> ALB
    ALB --> GW

    %% K8s Routing
    GW --> RouteU & RouteP & RouteO & RoutePay & RouteN & RouteArgo & RouteGraf

    RouteU --> User
    RouteP --> Product
    RouteO --> Order
    RoutePay --> Payment
    RouteN --> Notify

    %% gRPC Inter-Service Communication
    User -.->|"gRPC :50051"| Notify
    Order -.->|"gRPC :50051"| Notify
    Order -.->|"gRPC :50051"| Product
    Payment -.->|"gRPC :50051"| Notify

    %% DB Connections
    User ===> DB_User
    Product ===> DB_Prod
    Order ===> DB_Order
    Payment ===> DB_Pay
    Notify ===> DB_Notify

    style CDN fill:#1e293b,stroke:#06b6d4,stroke-width:2px,color:#fff
    style WAF fill:#f43f5e,stroke:#fff,stroke-width:1px,color:#fff
    style TLS fill:#10b981,stroke:#fff,stroke-width:1px,color:#fff
    style GW fill:#8b5cf6,stroke:#fff,stroke-width:1px,color:#fff
    style User fill:#3b82f6,stroke:#fff,stroke-width:1px,color:#fff
    style Product fill:#10b981,stroke:#fff,stroke-width:1px,color:#fff
    style Order fill:#8b5cf6,stroke:#fff,stroke-width:1px,color:#fff
    style Payment fill:#06b6d4,stroke:#fff,stroke-width:1px,color:#fff
    style Notify fill:#f59e0b,stroke:#fff,stroke-width:1px,color:#fff
```

---

## 2. 🔄 gRPC Inter-Service Communication

Services communicate internally via **gRPC** (port 50051) for low-latency, type-safe calls. External clients use HTTP/REST (port 8000).

```mermaid
graph LR
    subgraph "External Traffic (HTTP REST :8000)"
        Client["Client / Browser"]
    end

    subgraph "gRPC Communication (:50051)"
        direction TB
        US["User Service"]
        OS["Order Service"]
        PS["Payment Service"]
        ProdS["Product Service<br/>🔷 gRPC Server"]
        NS["Notification Service<br/>🔷 gRPC Server"]
    end

    Client -->|"REST API"| US & OS & PS & ProdS & NS

    US -->|"gRPC: SendNotification"| NS
    OS -->|"gRPC: CheckStock / DeductStock"| ProdS
    OS -->|"gRPC: SendNotification"| NS
    PS -->|"gRPC: SendNotification"| NS

    style ProdS fill:#10b981,stroke:#fff,stroke-width:2px,color:#fff
    style NS fill:#f59e0b,stroke:#fff,stroke-width:2px,color:#fff
    style US fill:#3b82f6,stroke:#fff,stroke-width:1px,color:#fff
    style OS fill:#8b5cf6,stroke:#fff,stroke-width:1px,color:#fff
    style PS fill:#06b6d4,stroke:#fff,stroke-width:1px,color:#fff
```

### gRPC Service Contracts

| Proto File | gRPC Server | gRPC Clients | Methods |
|:---|:---|:---|:---|
| `notification.proto` | notification-service | user, order, payment | `SendNotification`, `SendBulkNotification` |
| `product.proto` | product-service | order-service | `GetProduct`, `CheckStock`, `DeductStock` |

---

## 3. 🧩 Core Architectural Design Decisions

### A. Database-per-Microservice Pattern
To avoid tight coupling and single-point-of-failures, the platform enforces strict data boundaries:
*   **Encapsulation**: Each microservice (`user`, `product`, `order`, `payment`, `notification`) connects **only** to its own isolated database instance/schema on the RDS PostgreSQL cluster.
*   **Independent Schemas**: No database joins are allowed across domain boundaries. If a service needs data from another domain, it communicates via **gRPC** (internal) or REST HTTP (external).
*   **Trade-off & Mitigation**:
    *   *Challenge*: Querying aggregated data (e.g., retrieving an order with complete user and product details) requires API stitching.
    *   *Design Solution*: The frontend handles client-side aggregation. Services use gRPC for high-performance internal data exchange (stock validation, notification dispatch).

### B. Dual-Protocol Architecture (HTTP + gRPC)
*   **External API**: FastAPI (HTTP :8000) serves client-facing REST endpoints with Swagger docs
*   **Internal Communication**: gRPC (:50051) handles service-to-service calls with type-safe protobuf contracts
*   **Benefits**: 10x faster than REST for internal calls, binary serialization, streaming support, auto-generated client stubs

### C. Ingress Routing: Kubernetes Gateway API
The EKS cluster utilizes the next-generation **Kubernetes Gateway API** instead of standard legacy Ingress:
*   **Decoupled Roles**: Separates infrastructure provisioning (handled by the `Gateway` resource, mapped to the AWS ALB Controller) from routing logic (handled by individual `HTTPRoute` resources managed by development teams).
*   **Path-Based Dispatch**: Consolidates multiple domain routes onto a single ALB endpoint. This minimizes costs (saving ~$36/month per route compared to classic ELB-per-service topologies).
*   **TLS Termination**: ALB terminates HTTPS using an ACM certificate (self-signed for dev, DNS-validated for prod).

### D. Security-at-Depth & Perimeter Defense
Every layer of the request life-cycle enforces strict security controls:
1.  **TLS Encryption**: ALB terminates HTTPS with ACM certificate. HTTP→HTTPS redirect enforced.
2.  **Edge Protection** (prod): CloudFront CDN enforces SSL/TLS termination, edge caching, and custom header validation.
3.  **Firewall Auditing**: AWS WAF v2 applies OWASP protection rules, SQLi detection, and rate-limiting.
4.  **DDoS Protection**: Shield Standard (free, automatic) protects all AWS resources.
5.  **Cluster Zero-Trust**: Kubernetes NetworkPolicies restrict pod-to-pod traffic. gRPC port 50051 only open to services in the `ecommerce` namespace.
6.  **No Stored Keys**: OIDC federation for CI/CD (GitHub Actions) and IRSA for pod-level AWS access.

---

## 4. 🔐 TLS Architecture (Dev vs Production)

```mermaid
graph TD
    subgraph "Dev Environment (sslip.io)"
        DevClient["Browser"] -->|"HTTPS (self-signed)"| DevALB["ALB :443"]
        DevALB -->|"ACM self-signed cert"| DevCert["tls_self_signed_cert<br/>(Terraform)"]
        DevALB -->|"HTTP :80 → :443 redirect"| DevALB
        DevALB --> DevPods["Pods :8000"]
    end

    subgraph "Production Environment (custom domain)"
        ProdClient["Browser"] -->|"HTTPS (trusted CA)"| ProdCF["CloudFront"]
        ProdCF --> ProdWAF["WAF v2"]
        ProdWAF --> ProdALB["ALB :443"]
        ProdALB -->|"ACM DNS-validated cert"| ProdCert["Route53 validation"]
        ProdALB --> ProdPods["Pods :8000"]
    end

    style DevCert fill:#f59e0b,stroke:#fff,color:#fff
    style ProdCert fill:#10b981,stroke:#fff,color:#fff
```

| Feature | Dev | Production |
|:---|:---|:---|
| **Domain** | `*.sslip.io` (free) | Custom domain via Route53 |
| **Certificate** | Self-signed (ACM import) | DNS-validated (ACM managed) |
| **TLS Version** | TLS 1.2+ | TLS 1.3 |
| **CDN** | None (direct ALB) | CloudFront |
| **Cost** | $0 | ~$36/mo (CloudFront + Route53) |

---

## 5. 💾 Data Topology & Models Spec

The system stores domain models across distinct, optimized relational tables:

```mermaid
erDiagram
    USER_DB {
        int id PK
        varchar email UK
        varchar username UK
        varchar full_name
        varchar hashed_password
        bool is_active
        bool is_verified
        timestamp created_at
    }

    PRODUCT_DB {
        int id PK
        varchar name
        varchar sku UK
        decimal price
        varchar category
        int stock_quantity
        bool is_active
        timestamp created_at
    }

    ORDER_DB {
        int id PK
        int user_id FK
        varchar status
        decimal total_amount
        jsonb items
        jsonb shipping_address
        timestamp created_at
    }

    PAYMENT_DB {
        int id PK
        varchar payment_id UK
        int order_id FK
        int user_id FK
        decimal amount
        varchar currency
        varchar status
        varchar payment_method
        timestamp created_at
    }

    NOTIFICATION_DB {
        int id PK
        int user_id FK
        varchar type
        varchar subject
        text message
        varchar status
        jsonb metadata
        timestamp created_at
    }

    USER_DB ||--o{ ORDER_DB : "places orders"
    USER_DB ||--o{ NOTIFICATION_DB : "receives notifications"
    ORDER_DB ||--o{ PAYMENT_DB : "has payments"
    PRODUCT_DB ||--o{ ORDER_DB : "ordered in"
```

| Database | Main Tables | Primary Purpose | Key Fields |
| :--- | :--- | :--- | :--- |
| **user_service** | `users` | Identity, authentication, profiles | `email` (Unique), `username` (Unique), `hashed_password` (SHA-256) |
| **product_service** | `products` | Catalog listing, pricing, stock levels | `sku` (Unique), `price` (Decimal), `stock_quantity` (Integer) |
| **order_service** | `orders` | Cart processing and checkout records | `user_id` (Index), `total_amount` (Decimal), `items` (JSONB) |
| **payment_service** | `payments` | Audit trail of financial transactions | `payment_id` (Unique), `order_id` (Index), `status` (Enum) |
| **notification_service** | `notifications` | Alert dispatch records (Email, SMS) | `user_id` (Index), `type` (Enum), `status` (Enum) |

---

## 6. 🏗️ CI/CD Pipeline Architecture

```mermaid
flowchart TD
    Push["git push origin main"] --> Detect{"Path Changed?"}

    Detect -->|"terraform/**"| TFPipeline["ci-terraform.yaml"]
    Detect -->|"services/**"| SvcPipeline["ci-service.yaml"]
    Detect -->|"Both"| Both["Both pipelines run in parallel"]

    subgraph "Infrastructure Pipeline"
        TFPipeline --> TFFormat["📐 Format & Validate"]
        TFFormat --> TFScan["🛡️ Security Scan<br/>(tfsec + checkov)"]
        TFScan --> TFApply["🚀 Terraform Apply<br/>VPC → EKS → RDS → Helm"]
        TFApply --> Bootstrap["🔧 Bootstrap<br/>kubectl apply + ArgoCD"]
    end

    subgraph "Service Pipeline"
        SvcPipeline --> SvcLint["📝 Lint & Test"]
        SvcLint --> SvcScan["🔍 SAST & SCA Scan"]
        SvcScan --> DockerBuild["🐳 Docker Build + Trivy"]
        DockerBuild --> ECRPush["📦 Push ECR + Cosign"]
        ECRPush --> HelmUpdate["📋 Update Helm values.yaml"]
        HelmUpdate --> ArgoSync["🔄 ArgoCD Auto-Sync"]
    end

    style Push fill:#3b82f6,stroke:#fff,color:#fff
    style TFApply fill:#10b981,stroke:#fff,color:#fff
    style ArgoSync fill:#8b5cf6,stroke:#fff,color:#fff
```

---

## 7. 📈 Horizontal Scalability & Fault Tolerance

### Stateless Compute
All microservices are fully **stateless**. No session state is held in the containers.
*   **Client Session**: Authenticated user payload and shopping cart items are held in the client's web browser (`localStorage` / SPA memory), and credentials are sent on each transaction.
*   **Autoscaling**: EKS node pools and pods automatically scale up using a Horizontal Pod Autoscaler (HPA) tracking resource utilization thresholds (CPU > 80% or Memory > 85%).
*   **Self-Healing**: If a container crashes, K8s automatically terminates it and starts a healthy replacement, routing traffic only after the `/readyz` probe returns success.

### Database High Availability
*   **Multi-AZ Clustering**: The production PostgreSQL instance runs in a Multi-AZ cluster. Reads and writes land on the primary database, while changes are synchronously replicated to a standby database in a separate availability zone.
*   **Automatic Failover**: If the primary database zone experiences an outage, AWS Route 53 DNS automatically points the database endpoint to the standby zone within seconds with zero developer intervention.

---

## 8. 🌐 Network Architecture

```mermaid
graph TB
    subgraph "AWS VPC (10.1.0.0/16)"
        subgraph "Public Subnets"
            NAT["NAT Gateway"]
            EALB["ALB (internet-facing)"]
        end

        subgraph "Private Subnets (App)"
            EKS["EKS Nodes (t3.medium SPOT)"]
            PODS["Microservice Pods"]
        end

        subgraph "Private Subnets (DB)"
            RDS["RDS PostgreSQL"]
        end
    end

    Internet["Internet"] --> EALB
    EALB --> PODS
    PODS --> RDS
    PODS -->|"outbound"| NAT --> Internet

    style EALB fill:#8b5cf6,stroke:#fff,color:#fff
    style RDS fill:#3b82f6,stroke:#fff,color:#fff
    style EKS fill:#10b981,stroke:#fff,color:#fff
```

---

## 9. 💰 Cost Comparison (Dev vs Production)

| Resource | Dev (sslip.io) | Production |
|:---|:---|:---|
| **Domain** | sslip.io (free) | Route53 ($0.50/mo) |
| **TLS Certificate** | Self-signed ACM (free) | DNS-validated ACM (free) |
| **CDN** | None | CloudFront (~$5-36/mo) |
| **EKS Nodes** | 2× t3.medium SPOT (~$30/mo) | 3× m6i.xlarge ON_DEMAND (~$300/mo) |
| **RDS** | db.t4g.medium Single-AZ (~$49/mo) | db.r6g.large Multi-AZ (~$300/mo) |
| **Shield** | Standard (free) | Advanced ($3,000/mo) |
| **WAF** | Optional | $5/mo + $1/rule |
| **NAT Gateway** | Single (~$32/mo) | HA per-AZ (~$96/mo) |
| **Estimated Total** | **~$110/mo** | **~$3,700/mo** |
