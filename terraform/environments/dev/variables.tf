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
  description = "Domain name for the application (sslip.io for dev, custom domain for prod)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Existing Route53 hosted zone ID (empty for dev/sslip.io)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.31"
}

variable "enable_sslip_io" {
  description = "Use sslip.io free domains instead of Route53 (set true for dev)"
  type        = bool
  default     = true
}

################################################################################
# GitHub Actions OIDC
################################################################################

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}
