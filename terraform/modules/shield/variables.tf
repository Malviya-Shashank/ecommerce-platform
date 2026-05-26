variable "project_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "enable_shield" {
  description = "Enable Shield Advanced ($3000/month)"
  type        = bool
  default     = false
}
variable "cloudfront_distribution_arn" {
  type    = string
  default = ""
}
variable "alb_arn" {
  type    = string
  default = ""
}
variable "hosted_zone_id" {
  type    = string
  default = ""
}
variable "enable_proactive_engagement" {
  type    = bool
  default = false
}
variable "emergency_contacts" {
  type = list(object({
    email = string
    phone = string
    notes = string
  }))
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
