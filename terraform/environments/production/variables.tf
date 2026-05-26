################################################################################
# General
################################################################################

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "ecommerce"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "hosted_zone_id" {
  description = "Existing Route53 hosted zone ID"
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "Create a new Route53 hosted zone"
  type        = bool
  default     = false
}

################################################################################
# VPC
################################################################################

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_ha_nat" {
  description = "Enable HA NAT Gateway (one per AZ)"
  type        = bool
  default     = true
}

################################################################################
# EKS
################################################################################

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.31"
}

variable "eks_public_access" {
  description = "Enable public access to EKS API"
  type        = bool
  default     = true
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to access EKS API publicly"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "EKS node instance types"
  type        = list(string)
  default     = ["m6i.xlarge"]
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

################################################################################
# RDS
################################################################################

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "rds_allocated_storage" {
  type    = number
  default = 100
}

variable "rds_max_allocated_storage" {
  type    = number
  default = 500
}

################################################################################
# WAF / Shield
################################################################################

variable "waf_rate_limit" {
  description = "WAF rate limit per IP per 5 minutes"
  type        = number
  default     = 2000
}

variable "enable_bot_control" {
  type    = bool
  default = false
}

variable "enable_shield_advanced" {
  description = "Enable Shield Advanced ($3000/month)"
  type        = bool
  default     = false
}

################################################################################
# ALB (populated after Gateway creates it)
################################################################################

variable "alb_dns_name" {
  description = "ALB DNS name (populated after first apply when Gateway creates it)"
  type        = string
  default     = ""
}

variable "alb_arn" {
  description = "ALB ARN for Shield protection"
  type        = string
  default     = ""
}

################################################################################
# GitHub Actions OIDC
################################################################################

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

################################################################################
# Grafana
################################################################################

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "ChangeMeInProduction123!"
}
