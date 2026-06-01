variable "project_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "shield_tier" {
  description = "Shield tier: 'standard' (free, automatic) or 'advanced' ($3000/month)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "advanced"], var.shield_tier)
    error_message = "shield_tier must be 'standard' or 'advanced'."
  }
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
