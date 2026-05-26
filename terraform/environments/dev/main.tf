################################################################################
# Dev Environment - Root Module (cost-optimized)
################################################################################

locals {
  project_name = var.project_name
  environment  = "dev"
  cluster_name = "${var.project_name}-${local.environment}-eks"

  common_tags = {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source = "../../modules/vpc"

  project_name         = local.project_name
  environment          = local.environment
  vpc_cidr             = var.vpc_cidr
  az_count             = 2 # Only 2 AZs for dev
  cluster_name         = local.cluster_name
  enable_ha_nat        = false # Single NAT for cost savings
  enable_flow_logs     = false # Disable in dev
  enable_vpc_endpoints = false
  aws_region           = var.aws_region
  tags                 = local.common_tags
}

module "security_groups" {
  source = "../../modules/security-groups"

  project_name                  = local.project_name
  environment                   = local.environment
  vpc_id                        = module.vpc.vpc_id
  vpc_cidr                      = var.vpc_cidr
  cluster_name                  = local.cluster_name
  eks_cluster_security_group_id = module.eks.cluster_security_group_id
  tags                          = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name           = local.cluster_name
  cluster_version        = var.eks_cluster_version
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  node_security_group_id = module.security_groups.eks_nodes_security_group_id

  # Smaller nodes for dev
  node_instance_types = ["m6i.large"]
  capacity_type       = "SPOT" # Use spot for dev
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 3

  # Shorter log retention
  log_retention_days = 7

  tags = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  project_name          = local.project_name
  environment           = local.environment
  instance_class        = "db.t4g.medium" # Smaller for dev
  allocated_storage     = 20
  max_allocated_storage = 50
  multi_az              = false # No Multi-AZ in dev
  backup_retention_period = 7
  db_subnet_group_name  = module.vpc.db_subnet_group_name
  rds_security_group_id = module.security_groups.rds_security_group_id

  service_databases = [
    "user-service",
    "product-service",
    "order-service",
    "payment-service",
    "notification-service"
  ]

  tags = local.common_tags
}

resource "aws_s3_bucket" "loki_irsa" {
  bucket = "${local.project_name}-${local.environment}-loki-chunks"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "loki_irsa" {
  bucket                  = aws_s3_bucket.loki_irsa.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "irsa" {
  source = "../../modules/irsa"

  cluster_name       = local.cluster_name
  oidc_provider_url  = module.eks.oidc_provider_url
  oidc_provider_arn  = module.eks.oidc_provider_arn
  aws_region         = var.aws_region
  account_id         = data.aws_caller_identity.current.account_id
  project_name       = local.project_name
  rds_kms_key_arn    = module.rds.kms_key_arn
  loki_s3_bucket_arn = aws_s3_bucket.loki_irsa.arn
  hosted_zone_id     = var.hosted_zone_id
  tags               = local.common_tags
}

module "helm_releases" {
  source = "../../modules/helm-releases"

  cluster_name               = local.cluster_name
  environment                = local.environment
  project_name               = local.project_name
  aws_region                 = var.aws_region
  vpc_id                     = module.vpc.vpc_id
  domain_name                = var.domain_name
  aws_lb_controller_role_arn = module.irsa.aws_lb_controller_role_arn
  external_secrets_role_arn  = module.irsa.external_secrets_role_arn
  cert_manager_role_arn      = module.irsa.cert_manager_role_arn
  loki_role_arn              = module.irsa.loki_role_arn

  eks_node_group_dependency = module.eks.cluster_name

  tags = local.common_tags
}

# ECR repos (shared across environments, only create in one place)
# Dev uses the same ECR repos created by production

################################################################################
# GitHub Actions OIDC (No Stored Credentials)
################################################################################

module "github_oidc" {
  source = "../../modules/github-oidc"

  project_name = local.project_name
  environment  = local.environment
  aws_region   = var.aws_region
  github_org   = var.github_org
  github_repo  = var.github_repo
  tags         = local.common_tags
}
