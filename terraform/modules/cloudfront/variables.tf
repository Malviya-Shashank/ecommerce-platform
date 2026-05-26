variable "project_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "alb_dns_name" {
  description = "ALB DNS name to use as origin"
  type        = string
}
variable "acm_certificate_arn" {
  description = "ACM certificate ARN (must be in us-east-1 for CloudFront)"
  type        = string
}
variable "domain_aliases" {
  description = "List of domain aliases for CloudFront"
  type        = list(string)
}
variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN to associate with CloudFront"
  type        = string
  default     = null
}
variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_200"
}
variable "geo_restriction_type" {
  description = "Geo restriction type (none, whitelist, blacklist)"
  type        = string
  default     = "none"
}
variable "geo_restriction_locations" {
  description = "Country codes for geo restriction"
  type        = list(string)
  default     = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
