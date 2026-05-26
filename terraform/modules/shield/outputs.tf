output "cloudfront_protection_id" {
  value = var.enable_shield ? aws_shield_protection.cloudfront[0].id : null
}
output "alb_protection_id" {
  value = var.enable_shield ? aws_shield_protection.alb[0].id : null
}
