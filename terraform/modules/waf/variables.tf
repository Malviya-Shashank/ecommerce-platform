variable "project_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "scope" {
  description = "WAF scope: CLOUDFRONT or REGIONAL"
  type        = string
  default     = "CLOUDFRONT"
}
variable "rate_limit" {
  description = "Rate limit per IP per 5-minute period"
  type        = number
  default     = 2000
}
variable "enable_bot_control" {
  description = "Enable AWS Bot Control managed rule (additional cost)"
  type        = bool
  default     = false
}
variable "enable_logging" {
  description = "Enable WAF logging"
  type        = bool
  default     = true
}
variable "tags" {
  type    = map(string)
  default = {}
}
