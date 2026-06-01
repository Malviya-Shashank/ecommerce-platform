################################################################################
# Dev Environment Outputs
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = module.github_oidc.github_actions_role_arn
}

output "shield_tier" {
  description = "Active Shield tier (standard = free, advanced = $3000/mo)"
  value       = module.shield.shield_tier
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (self-signed for dev, DNS-validated for prod)"
  value       = module.acm_self_signed.certificate_arn
}

output "sslip_io_info" {
  description = "Instructions for sslip.io domain setup"
  value       = <<-EOT
    ┌─────────────────────────────────────────────────────────────┐
    │ sslip.io Domain Setup                                       │
    │                                                             │
    │ After ALB is provisioned by the Gateway controller, run:    │
    │   ./scripts/setup-sslip-domain.sh                          │
    │                                                             │
    │ This will:                                                  │
    │   1. Detect the ALB IP address                              │
    │   2. Construct sslip.io domains                             │
    │   3. Patch HTTPRoutes with the correct hostnames            │
    │   4. Print all accessible URLs                              │
    └─────────────────────────────────────────────────────────────┘
  EOT
}
