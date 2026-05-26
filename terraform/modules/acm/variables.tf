variable "project_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "domain_name" {
  description = "Primary domain for the certificate"
  type        = string
}
variable "subject_alternative_names" {
  description = "SANs for the certificate"
  type        = list(string)
  default     = []
}
variable "validation_route53_records" {
  description = "Route53 records created for validation"
  type = list(object({
    fqdn = string
  }))
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
