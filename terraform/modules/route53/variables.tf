variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  description = "Domain name (e.g., example.com)"
  type        = string
}

variable "create_zone" {
  description = "Create a new hosted zone or use existing"
  type        = bool
  default     = false
}

variable "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  type        = string
}

variable "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID (always Z2FDTNDATAQYW2)"
  type        = string
  default     = "Z2FDTNDATAQYW2"
}

variable "acm_domain_validation_options" {
  description = "ACM domain validation options for DNS records"
  type = map(object({
    resource_record_name  = string
    resource_record_type  = string
    resource_record_value = string
  }))
  default = {}
}

variable "alb_dns_name" {
  description = "ALB DNS name for health check"
  type        = string
  default     = ""
}

variable "enable_health_check" {
  description = "Enable Route53 health check for ALB"
  type        = bool
  default     = false
}

variable "enable_dnssec" {
  description = "Enable DNSSEC"
  type        = bool
  default     = false
}

variable "dnssec_kms_key_arn" {
  description = "KMS key ARN for DNSSEC signing"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
