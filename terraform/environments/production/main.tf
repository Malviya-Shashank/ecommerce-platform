################################################################################
# Production Environment - Root Module
################################################################################

locals {
  project_name = var.project_name
  environment  = "production"
  cluster_name = "${var.project_name}-${local.environment}-eks"

  common_tags = {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Team        = "platform"
  }
}

data "aws_caller_identity" "current" {}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  project_name        = local.project_name
  environment         = local.environment
  vpc_cidr            = var.vpc_cidr
  az_count            = 3
  cluster_name        = local.cluster_name
  enable_ha_nat       = var.enable_ha_nat
  enable_flow_logs    = true
  enable_vpc_endpoints = true
  aws_region          = var.aws_region
  tags                = local.common_tags
}

################################################################################
# Security Groups
################################################################################

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

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name           = local.cluster_name
  cluster_version        = var.eks_cluster_version
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  node_security_group_id = module.security_groups.eks_nodes_security_group_id
  enable_public_access   = var.eks_public_access
  public_access_cidrs    = var.eks_public_access_cidrs

  # Node group
  node_instance_types = var.node_instance_types
  capacity_type       = var.capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  tags = local.common_tags
}

################################################################################
# RDS PostgreSQL
################################################################################

module "rds" {
  source = "../../modules/rds"

  project_name          = local.project_name
  environment           = local.environment
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  multi_az              = true
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

################################################################################
# Loki S3 Bucket (created by helm-releases module, need ARN for IRSA)
# We create a placeholder for the circular dependency resolution
################################################################################

resource "aws_s3_bucket" "loki_irsa" {
  bucket = "${local.project_name}-${local.environment}-loki-chunks"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-${local.environment}-loki-chunks"
  })
}

resource "aws_s3_bucket_public_access_block" "loki_irsa" {
  bucket = aws_s3_bucket.loki_irsa.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# IRSA (IAM Roles for Service Accounts)
################################################################################

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

################################################################################
# Helm Releases (Platform Services)
################################################################################

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
  grafana_admin_password     = var.grafana_admin_password

  eks_node_group_dependency = module.eks.cluster_name

  tags = local.common_tags
}

################################################################################
# ACM Certificate (us-east-1 for CloudFront)
################################################################################

module "acm" {
  source = "../../modules/acm"

  providers = {
    aws = aws.us_east_1
  }

  project_name = local.project_name
  environment  = local.environment
  domain_name  = "*.${var.domain_name}"

  subject_alternative_names = [
    var.domain_name,
    "api.${var.domain_name}",
    "argocd.${var.domain_name}",
    "grafana.${var.domain_name}",
  ]

  tags = local.common_tags
}

################################################################################
# WAF (us-east-1 for CloudFront scope)
################################################################################

module "waf" {
  source = "../../modules/waf"

  providers = {
    aws = aws.us_east_1
  }

  project_name       = local.project_name
  environment        = local.environment
  scope              = "CLOUDFRONT"
  rate_limit         = var.waf_rate_limit
  enable_bot_control = var.enable_bot_control
  tags               = local.common_tags
}

################################################################################
# CloudFront Distribution
################################################################################

module "cloudfront" {
  source = "../../modules/cloudfront"

  project_name        = local.project_name
  environment         = local.environment
  alb_dns_name        = var.alb_dns_name # Will be populated after Gateway creates ALB
  acm_certificate_arn = module.acm.certificate_arn
  waf_web_acl_arn     = module.waf.web_acl_arn

  domain_aliases = [
    "api.${var.domain_name}",
    "argocd.${var.domain_name}",
    "grafana.${var.domain_name}",
  ]

  tags = local.common_tags
}

################################################################################
# Route53 DNS
################################################################################

module "route53" {
  source = "../../modules/route53"

  project_name           = local.project_name
  environment            = local.environment
  domain_name            = var.domain_name
  create_zone            = var.create_hosted_zone
  cloudfront_domain_name = module.cloudfront.distribution_domain_name

  acm_domain_validation_options = module.acm.domain_validation_options

  tags = local.common_tags
}

################################################################################
# Shield Advanced (Optional - $3000/month)
################################################################################

module "shield" {
  source = "../../modules/shield"

  project_name               = local.project_name
  environment                = local.environment
  enable_shield              = var.enable_shield_advanced
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
  alb_arn                    = var.alb_arn
  hosted_zone_id             = var.hosted_zone_id
  tags                       = local.common_tags
}

################################################################################
# GitHub Actions OIDC Provider (No Stored Credentials)
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


################################################################################
# ECR Repositories (one per microservice)
################################################################################

resource "aws_ecr_repository" "services" {
  for_each = toset([
    "user-service",
    "product-service",
    "order-service",
    "payment-service",
    "notification-service"
  ])

  name                 = "${local.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Service = each.key
  })
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
