variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "rds_kms_key_arn" {
  description = "KMS key ARN for RDS (used by External Secrets)"
  type        = string
}

variable "loki_s3_bucket_arn" {
  description = "S3 bucket ARN for Loki log storage"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID (for cert-manager)"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
