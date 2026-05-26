################################################################################
# Helm Releases Module - Variables
################################################################################

variable "cluster_name" {
  type = string
}

variable "environment" {
  description = "Environment (dev, staging, production)"
  type        = string
}

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "domain_name" {
  description = "Domain name for Grafana root_url"
  type        = string
}

# IRSA Role ARNs
variable "aws_lb_controller_role_arn" {
  type = string
}

variable "external_secrets_role_arn" {
  type = string
}

variable "cert_manager_role_arn" {
  type = string
}

variable "loki_role_arn" {
  type = string
}

# Grafana
variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "admin" # Should be overridden via tfvars or secrets
}

# Dependency
variable "eks_node_group_dependency" {
  description = "Dependency to ensure nodes are ready before deploying Helm charts"
  type        = any
  default     = null
}

# Chart Versions
variable "aws_lb_controller_version" {
  type    = string
  default = "1.10.0"
}

variable "gateway_api_version" {
  type    = string
  default = "1.2.1"
}

variable "argocd_version" {
  type    = string
  default = "7.7.5"
}

variable "prometheus_stack_version" {
  type    = string
  default = "67.4.0"
}

variable "loki_version" {
  type    = string
  default = "6.23.0"
}

variable "promtail_version" {
  type    = string
  default = "6.16.6"
}

variable "grafana_version" {
  type    = string
  default = "8.8.2"
}

variable "external_secrets_version" {
  type    = string
  default = "0.12.1"
}

variable "cert_manager_version" {
  type    = string
  default = "1.16.3"
}

variable "metrics_server_version" {
  type    = string
  default = "3.12.2"
}

variable "tags" {
  type    = map(string)
  default = {}
}
