output "shield_tier" {
  description = "Active Shield tier (standard = free, advanced = $3000/mo)"
  value       = var.shield_tier
}

output "cloudfront_protection_id" {
  value = var.shield_tier == "advanced" ? aws_shield_protection.cloudfront[0].id : null
}

output "alb_protection_id" {
  value = var.shield_tier == "advanced" ? aws_shield_protection.alb[0].id : null
}
