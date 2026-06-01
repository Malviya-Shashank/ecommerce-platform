# 🏗️ SETUP.md — Complete AWS Infrastructure Setup Guide

This document walks you through **every single step** required to set up the E-Commerce Platform infrastructure on AWS from scratch. Each step explains **What** you're doing, **Why** it's needed, **How** it works, and the exact **Commands** to run.

> After completing the one-time setup (Steps 1–6), all future infrastructure changes are **fully automated** via GitHub Actions. Just `git push` to `main`.

---

## 📋 Prerequisites

Before starting, ensure you have these tools installed on your local machine:

| Tool | Version | Why It's Needed | Install Command |
|------|---------|-----------------|-----------------|
| **AWS CLI** | v2.x | Authenticates with your AWS account and creates resources | `brew install awscli` (macOS) or [AWS Docs](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| **Terraform** | ≥ 1.9.0 | Infrastructure as Code engine — creates VPC, EKS, RDS, etc. | `brew install terraform` or [Download](https://developer.hashicorp.com/terraform/install) |
| **kubectl** | v1.31+ | Kubernetes command-line tool — talks to your EKS cluster | `brew install kubectl` or [Docs](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | v3.x | Kubernetes package manager — not needed locally (Terraform handles it), but useful for debugging | `brew install helm` |
| **Docker** | v24+ | Build container images locally (optional — CI handles this) | [Docker Desktop](https://www.docker.com/products/docker-desktop/) |
| **Git** | v2.x | Version control — push changes to trigger CI/CD | `brew install git` |

**AWS Requirements:**
- An AWS account with **AdministratorAccess** (for the initial setup only)
- A GitHub account with the repository: `Malviya-Shashank/ecommerce-platform`

---

## Step 1: Configure AWS CLI Authentication

### 📌 What
Configure the AWS CLI with credentials so your local terminal can create AWS resources.

### 🤔 Why
Terraform and AWS CLI commands need to authenticate with your AWS account. Without this, no AWS resources can be created. We use IAM credentials for the one-time bootstrap, then switch to OIDC (keyless) for all CI/CD.

### ⚙️ How It Works
The AWS CLI stores credentials in `~/.aws/credentials` and uses them to sign API requests to AWS. You'll use an IAM user with AdministratorAccess for the initial setup only. After Terraform creates the OIDC provider, GitHub Actions will use short-lived tokens instead of stored keys.

### 💻 Commands

```bash
# Step 1a: Configure AWS CLI with your IAM credentials
aws configure
```

You'll be prompted for:
```
AWS Access Key ID:     <your-access-key-id>
AWS Secret Access Key: <your-secret-access-key>
Default region name:   ap-south-1
Default output format: json
```

```bash
# Step 1b: Verify authentication works
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

> ⚠️ **Note:** If you're using AWS SSO or an organization, use `aws sso login --profile your-profile` instead.

---

## Step 2: Create Terraform State Backend (S3 Bucket)

### 📌 What
Create an S3 bucket that stores your Terraform state file — the single source of truth for what infrastructure exists.

### 🤔 Why
Terraform needs to know what resources it has already created. Without remote state:
- Multiple people can't work on the infrastructure simultaneously (state conflicts)
- If your local machine dies, you lose track of what exists in AWS
- CI/CD pipelines (GitHub Actions) can't access the state

The S3 backend with `use_lockfile = true` also prevents concurrent Terraform runs from corrupting state.

### ⚙️ How It Works
1. An S3 bucket named `ecommerce-platform-terraform-state` is created
2. Versioning is enabled so you can recover previous state if something goes wrong
3. Server-side encryption (AES-256) encrypts the state at rest
4. Public access is completely blocked
5. Terraform uses native S3 lockfiles (no DynamoDB needed — requires Terraform ≥ 1.10)

**File Reference:** [backend.tf](file:///Users/shashankmalviya/Documents/Project/terraform/environments/dev/backend.tf) — tells Terraform where to store state

### 💻 Commands

```bash
# Step 2a: Navigate to the project root
cd /path/to/ecommerce-platform

# Step 2b: Make the setup script executable
chmod +x scripts/setup.sh

# Step 2c: Run the setup script
# Arguments: <project-name> <aws-region>
./scripts/setup.sh ecommerce ap-south-1
```

**What the script does internally:**
```bash
# Creates the S3 bucket
aws s3api create-bucket \
    --bucket "ecommerce-platform-terraform-state" \
    --region "ap-south-1" \
    --create-bucket-configuration LocationConstraint="ap-south-1"

# Enables versioning (state history)
aws s3api put-bucket-versioning \
    --bucket "ecommerce-platform-terraform-state" \
    --versioning-configuration Status=Enabled

# Enables encryption at rest
aws s3api put-bucket-encryption \
    --bucket "ecommerce-platform-terraform-state" \
    --server-side-encryption-configuration '{
        "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

# Blocks all public access
aws s3api put-public-access-block \
    --bucket "ecommerce-platform-terraform-state" \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'
```

**Expected output:**
```
🚀 Setting up Terraform backend for ecommerce in ap-south-1...
📦 Creating S3 bucket for Terraform state...
✅ Setup complete!
```

```bash
# Step 2d: Verify the bucket was created
aws s3 ls | grep ecommerce-platform-terraform-state
```

---

## Step 3: Configure Terraform Variables

### 📌 What
Set environment-specific values (domain name, GitHub org, region) that Terraform uses when creating resources.

### 🤔 Why
The Terraform modules are generic and reusable. Variables allow the same modules to create different infrastructure for dev, staging, and production. Without correct variables, Terraform would use defaults that may not match your AWS account or GitHub repo.

### ⚙️ How It Works
Terraform reads `terraform.tfvars` at plan/apply time. The values flow into modules:
- `project_name` → Prefixes all resource names (e.g., `ecommerce-dev-eks`)
- `aws_region` → Where to create resources (Mumbai: `ap-south-1`)
- `domain_name` → For dev, set to `sslip.io` (free domain, no Route53 needed)
- `enable_sslip_io` → Set `true` for dev (uses free sslip.io domains instead of Route53)
- `github_org` / `github_repo` → Scopes the OIDC trust policy to your repo only

**File Reference:** [terraform.tfvars](file:///Users/shashankmalviya/Documents/Project/terraform/environments/dev/terraform.tfvars)

### 💻 Commands

```bash
# Step 3a: Navigate to the dev environment
cd terraform/environments/dev

# Step 3b: Edit the terraform.tfvars file with your actual values
```

Update the file with your values:
```hcl
# Dev Environment Variables
project_name    = "ecommerce"
aws_region      = "ap-south-1"
domain_name     = "sslip.io"             # Free domain — no Route53 costs
enable_sslip_io = true                   # Use sslip.io instead of Route53
vpc_cidr        = "10.1.0.0/16"

# GitHub Actions OIDC
github_org  = "Malviya-Shashank"        # ← Your GitHub username or org
github_repo = "ecommerce-platform"      # ← Your GitHub repository name
```

> 💡 **Tip:** The `.gitignore` excludes `*.tfvars` by default to prevent secrets from being committed. This file stays local.

---

## Step 4: Initialize & Apply Terraform (First-Time Manual Deploy)

### 📌 What
Run Terraform to create the entire AWS infrastructure: VPC, EKS cluster, RDS database, IAM roles, and all Helm releases (ArgoCD, Prometheus, Grafana, Loki, etc.).

### 🤔 Why
This is a **chicken-and-egg** situation: GitHub Actions needs the OIDC IAM role to authenticate with AWS, but Terraform creates that role. So the **very first deploy must be done manually** from your local machine. After this, GitHub Actions takes over automatically.

### ⚙️ How It Works
Terraform processes your configuration in this order (respecting `depends_on`):

```
1. VPC Module          → Creates VPC, subnets, NAT gateway, route tables
2. Security Groups     → Creates firewall rules for EKS + RDS
3. EKS Module          → Creates EKS cluster, node groups, OIDC provider, add-ons
                          + Creates EKS Access Entry for GitHub Actions role
4. RDS Module          → Creates PostgreSQL database (Multi-AZ in prod)
5. S3 Bucket (Loki)    → Creates S3 bucket for log storage
6. IRSA Module         → Creates IAM roles for K8s service accounts
7. Helm Releases       → Installs ALL platform services (only AFTER nodes are Ready):
   ├── ArgoCD              (argocd namespace)
   ├── kube-prometheus-stack (monitoring namespace)
   ├── Grafana              (monitoring namespace)
   ├── Loki + Promtail      (monitoring namespace)
   ├── AWS LB Controller    (kube-system namespace)
   ├── Cert Manager         (cert-manager namespace)
   ├── External Secrets     (external-secrets namespace)
   ├── Metrics Server       (kube-system namespace)
   └── Gateway API CRDs     (gateway-system namespace)
8. GitHub OIDC Module  → Creates OIDC provider + IAM role for GitHub Actions
```

**Key:** Every Helm release has `depends_on = [var.eks_node_group_dependency]`, which means they **will not install** until the EKS cluster and nodes are fully created and healthy.

**File References:**
- [main.tf](file:///Users/shashankmalviya/Documents/Project/terraform/environments/dev/main.tf) — Module orchestration
- [providers.tf](file:///Users/shashankmalviya/Documents/Project/terraform/environments/dev/providers.tf) — AWS + Kubernetes + Helm provider config

### 💻 Commands

```bash
# Step 4a: Ensure you're in the dev environment directory
cd terraform/environments/dev

# Step 4b: Initialize Terraform (downloads providers, sets up S3 backend)
terraform init
```

**Expected output:**
```
Initializing the backend...
Successfully configured the backend "s3"!

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.80"...
- Finding hashicorp/kubernetes versions matching "~> 2.35"...
- Finding hashicorp/helm versions matching "~> 2.17"...
...
Terraform has been successfully initialized!
```

```bash
# Step 4c: Preview what Terraform will create (dry run)
terraform plan -out=tfplan
```

**Expected output:** A long list showing ~80-100 resources to be created. Review it carefully.

```bash
# Step 4d: Apply the plan — THIS CREATES REAL AWS RESOURCES
# ⏱️ This takes 15-25 minutes (EKS cluster creation is ~10 min)
terraform apply tfplan
```

**Expected output (at the end):**
```
Apply complete! Resources: ~95 added, 0 changed, 0 destroyed.

Outputs:

eks_cluster_endpoint = "https://XXXXXXXXXX.gr7.ap-south-1.eks.amazonaws.com"
eks_cluster_name = "ecommerce-dev-eks"
github_actions_role_arn = "arn:aws:iam::123456789012:role/ecommerce-dev-github-actions-role"
rds_endpoint = "ecommerce-dev-rds.XXXXX.ap-south-1.rds.amazonaws.com:5432"
vpc_id = "vpc-0abc123def456789"
```

> ⚠️ **Important:** Save the `github_actions_role_arn` output — you'll need it in Step 5.

```bash
# Step 4e: Note down the critical outputs
terraform output github_actions_role_arn
terraform output eks_cluster_name
terraform output eks_cluster_endpoint
```

---

## Step 5: Configure GitHub Repository Secrets

### 📌 What
Add the AWS OIDC role ARN and region as encrypted secrets in your GitHub repository settings.

### 🤔 Why
GitHub Actions needs to know **which IAM role to assume** when it runs. The OIDC role was created by Terraform in Step 4. GitHub secrets are encrypted at rest and only exposed to workflow runs — never visible in logs.

Without these secrets:
- `ci-terraform.yaml` → Terraform Apply will fail (can't authenticate to AWS)
- `ci-shared-template.yaml` → Docker image push to ECR will fail
- `bootstrap` stage → kubectl commands will fail (can't access EKS)

### ⚙️ How It Works
GitHub Actions uses OpenID Connect (OIDC) federation to get short-lived AWS credentials. The flow:
1. GitHub generates a signed JWT token for the workflow run
2. The `aws-actions/configure-aws-credentials@v4` action sends this token to AWS STS
3. AWS validates the token against the OIDC provider created by Terraform
4. AWS issues temporary credentials scoped to the `ecommerce-dev-github-actions-role`
5. All subsequent AWS CLI/Terraform/kubectl commands use these temp credentials

**No long-lived AWS keys are stored anywhere** — this is the most secure approach.

### 💻 Commands

**Option A: GitHub Web UI (Recommended)**

1. Go to your repository: `https://github.com/Malviya-Shashank/ecommerce-platform`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add:

| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_ARN` | `arn:aws:iam::<YOUR_ACCOUNT_ID>:role/ecommerce-dev-github-actions-role` |
| `AWS_REGION` | `ap-south-1` |

**Option B: GitHub CLI (if you have `gh` installed)**

```bash
# Step 5a: Install GitHub CLI (if not installed)
brew install gh

# Step 5b: Authenticate with GitHub
gh auth login

# Step 5c: Set the secrets
gh secret set AWS_ROLE_ARN --body "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/ecommerce-dev-github-actions-role"
gh secret set AWS_REGION --body "ap-south-1"
```

```bash
# Step 5d: Verify secrets are set
gh secret list
```

**Expected output:**
```
AWS_REGION      Updated 2026-05-28
AWS_ROLE_ARN    Updated 2026-05-28
```

---

## Step 6: Bootstrap ArgoCD & Kubernetes Manifests (First-Time)

### 📌 What
Connect your local `kubectl` to the EKS cluster, then apply the Kubernetes base manifests (namespaces, Gateway API routes) and bootstrap ArgoCD with the App-of-Apps pattern.

### 🤔 Why
Terraform already installed ArgoCD via Helm (Step 4), but ArgoCD doesn't know **which applications** to manage yet. We need to:
1. Create the Kubernetes namespaces (`ecommerce`, `monitoring`, `argocd`)
2. Set up the Gateway API routing (ALB → services)
3. Tell ArgoCD about our Git repository and which Helm charts to deploy

After this bootstrap, ArgoCD will **automatically deploy and manage** all 5 microservices.

### ⚙️ How It Works
1. `aws eks update-kubeconfig` configures `kubectl` to talk to your EKS cluster using IAM auth
2. `kubectl apply -f kubernetes/base/` creates namespaces and Gateway API resources
3. `kubectl apply -f argocd/projects/` creates an ArgoCD AppProject scoping what repos/namespaces are allowed
4. `kubectl apply -f argocd/app-of-apps.yaml` is the master trigger:
   - ArgoCD reads this Application manifest
   - Discovers child Application manifests in `argocd/applications/`
   - Each child points to a service's Helm chart (`services/<name>/helm/`)
   - ArgoCD installs all 5 microservices automatically
   - Enables auto-sync: any Git change → automatic redeployment

**File References:**
- [namespaces.yaml](file:///Users/shashankmalviya/Documents/Project/kubernetes/base/namespaces.yaml) — K8s namespaces
- [app-of-apps.yaml](file:///Users/shashankmalviya/Documents/Project/argocd/app-of-apps.yaml) — Master ArgoCD application
- [ecommerce.yaml](file:///Users/shashankmalviya/Documents/Project/argocd/projects/ecommerce.yaml) — ArgoCD project
- [services.yaml](file:///Users/shashankmalviya/Documents/Project/argocd/applications/services.yaml) — All 5 service applications

### 💻 Commands

```bash
# Step 6a: Configure kubectl to connect to EKS
aws eks update-kubeconfig \
    --name ecommerce-dev-eks \
    --region ap-south-1
```

**Expected output:**
```
Added new context arn:aws:eks:ap-south-1:123456789012:cluster/ecommerce-dev-eks to /Users/you/.kube/config
```

```bash
# Step 6b: Verify cluster connection
kubectl get nodes
```

**Expected output:**
```
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-1-1-xxx.ap-south-1.compute.internal     Ready    <none>   10m   v1.31.x
ip-10-1-2-xxx.ap-south-1.compute.internal     Ready    <none>   10m   v1.31.x
```

```bash
# Step 6c: Verify Helm releases installed by Terraform
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get pods -n kube-system | grep -E "aws-load-balancer|metrics-server"
```

**Expected output:** All pods should be `Running` or `Completed`.

```bash
# Step 6d: Apply Kubernetes base manifests (namespaces + Gateway API)
kubectl apply -f kubernetes/base/
```

**Expected output:**
```
namespace/ecommerce created
namespace/monitoring configured
namespace/argocd configured
gatewayclass.gateway.networking.k8s.io/amazon-alb created
gateway.gateway.networking.k8s.io/main-gateway created
httproute.gateway.networking.k8s.io/... created
```

```bash
# Step 6e: Apply ArgoCD project definition
kubectl apply -f argocd/projects/ecommerce.yaml
```

**Expected output:**
```
appproject.argoproj.io/ecommerce created
```

```bash
# Step 6f: Apply ArgoCD App-of-Apps (🚀 triggers full deployment!)
kubectl apply -f argocd/app-of-apps.yaml
```

**Expected output:**
```
application.argoproj.io/ecommerce-app-of-apps created
```

```bash
# Step 6g: Watch ArgoCD sync all applications (takes 2-5 minutes)
watch kubectl get applications -n argocd
```

**Expected output (after sync completes):**
```
NAME                     SYNC STATUS   HEALTH STATUS
ecommerce-app-of-apps    Synced        Healthy
user-service             Synced        Healthy
product-service          Synced        Healthy
order-service            Synced        Healthy
payment-service          Synced        Healthy
notification-service     Synced        Healthy
```

```bash
# Step 6h: Verify all pods are running
kubectl get pods -A
```

---

## Step 7: Verify Everything is Working

### 📌 What
Confirm that every layer of the infrastructure is operational — from AWS resources to Kubernetes pods to ArgoCD sync.

### 🤔 Why
This is your sanity check before enabling automated CI/CD. If anything is broken, it's easier to debug now than after pushing to GitHub Actions.

### 💻 Commands

```bash
# 1. Check AWS Infrastructure
echo "=== AWS VPC ==="
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=ecommerce" \
    --query "Vpcs[].{ID:VpcId,CIDR:CidrBlock}" --output table

echo "=== EKS Cluster ==="
aws eks describe-cluster --name ecommerce-dev-eks \
    --query "cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}" \
    --output table

echo "=== RDS Instance ==="
aws rds describe-db-instances \
    --query "DBInstances[?contains(DBInstanceIdentifier,'ecommerce')].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine}" \
    --output table
```

```bash
# 2. Check Kubernetes Cluster
echo "=== Nodes ==="
kubectl get nodes -o wide

echo "=== All Namespaces ==="
kubectl get namespaces

echo "=== All Pods ==="
kubectl get pods -A --sort-by=.metadata.namespace
```

```bash
# 3. Check Platform Services (installed by Terraform Helm)
echo "=== ArgoCD ==="
kubectl get pods -n argocd

echo "=== Monitoring (Prometheus + Grafana + Loki) ==="
kubectl get pods -n monitoring

echo "=== ALB Controller ==="
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

echo "=== Cert Manager ==="
kubectl get pods -n cert-manager

echo "=== External Secrets ==="
kubectl get pods -n external-secrets

echo "=== Gateway API ==="
kubectl get gateways,httproutes -A
```

```bash
# 4. Check ArgoCD Applications
kubectl get applications -n argocd -o wide
```

```bash
# 5. Get ArgoCD admin password (for web UI access)
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
echo ""
```

```bash
# 6. Port-forward to access ArgoCD UI locally
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Then open https://localhost:8080 in your browser
# Username: admin | Password: (from step 5 above)
```

```bash
# 7. Port-forward to access Grafana UI locally
kubectl port-forward svc/grafana -n monitoring 3000:3000
# Then open http://localhost:3000 in your browser
# Username: admin | Password: admin (or whatever is in tfvars)
```

---

## Step 8: Push to GitHub — Activate Automated CI/CD

### 📌 What
Push your code to GitHub. From this point onward, every push to `main` automatically updates infrastructure and deploys applications.

### 🤔 Why
This is the handoff from "manual setup" to "fully automated." After this step:
- **Terraform changes** (`terraform/**`) → Automatically applied by GitHub Actions
- **Service code changes** (`services/**`) → Automatically built, scanned, pushed to ECR, and deployed via ArgoCD
- **Kubernetes/ArgoCD changes** (`kubernetes/**`, `argocd/**`) → Automatically applied

You never need to run `terraform apply` or `kubectl apply` manually again.

### ⚙️ How It Works

**When you push terraform changes:**
```
ci-terraform.yaml:
  Format & Validate  →  Security Scan (tfsec + checkov)  →  Terraform Apply  →  Bootstrap ArgoCD
```

**When you push service code changes:**
```
ci-{service}.yaml → ci-shared-template.yaml:
  Lint & Test  →  SAST/SCA Scan  →  Build Docker + Trivy  →  Push ECR + Cosign  →  Update Helm values
                                                                                        ↓
                                                                              ArgoCD detects change
                                                                                        ↓
                                                                              Auto-syncs new pods
```

**File References:**
- [ci-terraform.yaml](file:///Users/shashankmalviya/Documents/Project/.github/workflows/ci-terraform.yaml) — Infrastructure pipeline
- [ci-shared-template.yaml](file:///Users/shashankmalviya/Documents/Project/.github/workflows/ci-shared-template.yaml) — Service CI pipeline

### 💻 Commands

```bash
# Step 8a: Ensure you're in the project root
cd /path/to/ecommerce-platform

# Step 8b: Check what files will be committed
git status

# Step 8c: Stage all changes
git add .

# Step 8d: Commit
git commit -m "feat: setup full GitOps CI/CD with automated terraform apply and argocd bootstrap"

# Step 8e: Push to main (🚀 triggers GitHub Actions!)
git push origin main
```

```bash
# Step 8f: Monitor the GitHub Actions pipeline
# Open in browser:
echo "https://github.com/Malviya-Shashank/ecommerce-platform/actions"
```

**What you'll see in GitHub Actions:**
1. ✅ `📐 Format & Validate` — Terraform fmt + validate passes
2. ✅ `🛡️ IaC Security Scan` — tfsec + Checkov scans pass
3. ✅ `🚀 Terraform Apply (Dev)` — Infrastructure applied (fast if no changes)
4. ✅ `🔧 Bootstrap ArgoCD & Gateway API` — Manifests applied, apps syncing

---

## Step 9: Set Up AWS Secrets Manager (For Application Databases)

### 📌 What
Create secrets in AWS Secrets Manager for the database credentials that your microservices need.

### 🤔 Why
Your microservices need database connection strings to connect to the RDS PostgreSQL instance. **Never hardcode credentials in code or environment variables.** Instead, the External Secrets Operator (installed by Terraform in Step 4) syncs secrets from AWS Secrets Manager into Kubernetes Secrets.

### ⚙️ How It Works
1. You create a secret in AWS Secrets Manager with DB credentials
2. An `ExternalSecret` K8s resource (in your Helm charts) references the AWS secret
3. The External Secrets Operator reads the AWS secret via IRSA (no stored credentials)
4. It creates/updates a native Kubernetes `Secret` that the pod mounts as environment variables
5. FastAPI reads the connection string on startup

### 💻 Commands

```bash
# Step 9a: Get the RDS endpoint from Terraform output
cd terraform/environments/dev
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
echo "RDS Endpoint: $RDS_ENDPOINT"

# Step 9b: Create database secrets in AWS Secrets Manager
# (Repeat for each service: user, product, order, payment, notification)
aws secretsmanager create-secret \
    --name "ecommerce/dev/user-service/db" \
    --secret-string '{
        "DB_HOST": "'$RDS_ENDPOINT'",
        "DB_PORT": "5432",
        "DB_NAME": "user_service",
        "DB_USER": "ecommerce_admin",
        "DB_PASSWORD": "YOUR_SECURE_PASSWORD_HERE"
    }' \
    --region ap-south-1

aws secretsmanager create-secret \
    --name "ecommerce/dev/product-service/db" \
    --secret-string '{
        "DB_HOST": "'$RDS_ENDPOINT'",
        "DB_PORT": "5432",
        "DB_NAME": "product_service",
        "DB_USER": "ecommerce_admin",
        "DB_PASSWORD": "YOUR_SECURE_PASSWORD_HERE"
    }' \
    --region ap-south-1

aws secretsmanager create-secret \
    --name "ecommerce/dev/order-service/db" \
    --secret-string '{
        "DB_HOST": "'$RDS_ENDPOINT'",
        "DB_PORT": "5432",
        "DB_NAME": "order_service",
        "DB_USER": "ecommerce_admin",
        "DB_PASSWORD": "YOUR_SECURE_PASSWORD_HERE"
    }' \
    --region ap-south-1

aws secretsmanager create-secret \
    --name "ecommerce/dev/payment-service/db" \
    --secret-string '{
        "DB_HOST": "'$RDS_ENDPOINT'",
        "DB_PORT": "5432",
        "DB_NAME": "payment_service",
        "DB_USER": "ecommerce_admin",
        "DB_PASSWORD": "YOUR_SECURE_PASSWORD_HERE"
    }' \
    --region ap-south-1

aws secretsmanager create-secret \
    --name "ecommerce/dev/notification-service/db" \
    --secret-string '{
        "DB_HOST": "'$RDS_ENDPOINT'",
        "DB_PORT": "5432",
        "DB_NAME": "notification_service",
        "DB_USER": "ecommerce_admin",
        "DB_PASSWORD": "YOUR_SECURE_PASSWORD_HERE"
    }' \
    --region ap-south-1
```

```bash
# Step 9c: Verify secrets were created
aws secretsmanager list-secrets \
    --filters Key=name,Values=ecommerce/dev \
    --query "SecretList[].Name" \
    --output table
```

---

## Step 10: Seed the Production Database

### 📌 What
Initialize the PostgreSQL database schemas (create tables, indexes, seed data) for all 5 microservices.

### 🤔 Why
The RDS instance created by Terraform is an empty database server. Your microservices expect specific tables to exist. Without seeding, the services will crash on startup with "relation does not exist" errors.

### ⚙️ How It Works
You run the SQL init script against the RDS instance. Since RDS is in a private subnet (no public access), you have two options:
1. **Port-forward through a pod** — Use a temporary pod inside EKS to access the database
2. **Run as a Kubernetes Job** — Create a one-time job that runs the SQL script

### 💻 Commands

```bash
# Option A: Port-forward through a temporary PostgreSQL pod

# Step 10a: Run a temporary PostgreSQL client pod
kubectl run pg-client --rm -it \
    --image=postgres:16 \
    --namespace=ecommerce \
    --restart=Never \
    -- bash

# Step 10b: Inside the pod, connect to RDS and run the init script
# (Copy the SQL from scripts/init-db.sql)
psql -h <RDS_ENDPOINT> -U ecommerce_admin -d postgres

# Run the SQL commands from scripts/init-db.sql
# Then exit with: \q
# Then exit pod with: exit
```

```bash
# Option B: Apply the init script directly using kubectl

# Step 10b-alt: Create a ConfigMap with the SQL script
kubectl create configmap db-init-sql \
    --from-file=init-db.sql=scripts/init-db.sql \
    -n ecommerce

# Step 10c-alt: Run a Job that executes the SQL
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: db-init
  namespace: ecommerce
spec:
  template:
    spec:
      containers:
      - name: db-init
        image: postgres:16
        command: ["psql"]
        args: ["-h", "<RDS_ENDPOINT>", "-U", "ecommerce_admin", "-f", "/sql/init-db.sql"]
        env:
        - name: PGPASSWORD
          value: "YOUR_SECURE_PASSWORD_HERE"
        volumeMounts:
        - name: sql
          mountPath: /sql
      volumes:
      - name: sql
        configMap:
          name: db-init-sql
      restartPolicy: Never
  backoffLimit: 3
EOF

# Step 10d-alt: Check job completed
kubectl get jobs -n ecommerce
kubectl logs job/db-init -n ecommerce
```

---

## 🎉 Setup Complete!

Your infrastructure is now fully operational. Here's what exists:

```
AWS Account
├── VPC (10.1.0.0/16)
│   ├── Public Subnets (2x AZs)    ← NAT Gateway, ALB (HTTPS)
│   ├── Private Subnets (2x AZs)   ← EKS Nodes, Pods
│   └── Database Subnets (2x AZs)  ← RDS PostgreSQL
│
├── ACM Certificate (self-signed for dev, DNS-validated for prod)
│   └── Imported into ACM → ALB terminates HTTPS
│
├── EKS Cluster (ecommerce-dev-eks)
│   ├── 2x SPOT Nodes (t3.medium)  ← Cost-optimized
│   ├── ArgoCD          ← GitOps controller
│   ├── Prometheus       ← Metrics collection
│   ├── Grafana          ← Dashboards
│   ├── Loki + Promtail  ← Log aggregation (S3-backed)
│   ├── ALB Controller   ← Load balancer management (HTTPS)
│   ├── Cert Manager     ← TLS certificates
│   ├── External Secrets ← AWS Secrets Manager sync
│   ├── Metrics Server   ← HPA autoscaling
│   ├── Gateway API      ← Ingress routing (sslip.io domains)
│   └── 5 Microservices  ← Deployed by ArgoCD
│       ├── user-service           (:8000 REST, gRPC client)
│       ├── product-service        (:8000 REST, :50051 gRPC server)
│       ├── order-service          (:8000 REST, gRPC client)
│       ├── payment-service        (:8000 REST, gRPC client)
│       └── notification-service   (:8000 REST, :50051 gRPC server)
│
├── Shield Standard (free, automatic DDoS protection)
├── RDS PostgreSQL (Single-AZ in dev, Multi-AZ in prod)
├── S3 (Terraform state + Loki logs)
├── GitHub OIDC (keyless CI/CD auth)
└── KMS (encryption at rest)
```

### What Happens on Every `git push` to `main`:

| Changed Path | Pipeline | What Happens |
|-------------|----------|-------------|
| `terraform/**` | `ci-terraform.yaml` | Terraform Apply → Helm installs → ArgoCD bootstrap |
| `services/<name>/**` | `ci-<name>.yaml` | Build → Scan → Push ECR → Update Helm values → ArgoCD syncs |
| `argocd/**` | `ci-terraform.yaml` | Bootstrap stage re-applies ArgoCD manifests |
| `kubernetes/**` | `ci-terraform.yaml` | Bootstrap stage re-applies K8s base manifests |

### Quick Reference Commands

```bash
# Connect to cluster
aws eks update-kubeconfig --name ecommerce-dev-eks --region ap-south-1

# Check everything
kubectl get pods -A
kubectl get applications -n argocd

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access Grafana UI
kubectl port-forward svc/grafana -n monitoring 3000:3000

# Check logs of a service
kubectl logs -l app=user-service -n ecommerce --tail=100 -f

# Force ArgoCD re-sync
kubectl patch application ecommerce-app-of-apps -n argocd \
    --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'
```

---

## 🔥 Troubleshooting

### Terraform Apply fails with "Access Denied"
```bash
# Verify your AWS credentials
aws sts get-caller-identity

# Ensure you have AdministratorAccess for the first apply
aws iam list-attached-user-policies --user-name YOUR_IAM_USERNAME
```

### EKS nodes not becoming Ready
```bash
# Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>

# Check EKS add-ons
aws eks list-addons --cluster-name ecommerce-dev-eks
```

### Helm releases not installing
```bash
# Check if nodes are ready (Helm waits for nodes)
kubectl get nodes

# Check Terraform state for helm releases
cd terraform/environments/dev
terraform state list | grep helm
```

### ArgoCD not syncing applications
```bash
# Check ArgoCD server logs
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd --tail=50

# Check ArgoCD application status
kubectl get applications -n argocd -o yaml | grep -A5 "status:"

# Force a sync
kubectl patch application ecommerce-app-of-apps -n argocd \
    --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### GitHub Actions OIDC authentication fails
```bash
# Verify the OIDC provider exists
aws iam list-open-id-connect-providers

# Verify the IAM role trust policy
aws iam get-role --role-name ecommerce-dev-github-actions-role \
    --query "Role.AssumeRolePolicyDocument"

# Ensure GitHub secrets match the Terraform output
cd terraform/environments/dev
terraform output github_actions_role_arn
```
