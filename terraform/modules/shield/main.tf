################################################################################
# AWS Shield Module
#
# Shield Standard: FREE, automatic on all AWS accounts. No resources needed.
# Shield Advanced: $3,000/month. Requires explicit aws_shield_protection.
#
# For dev/learning: use shield_tier = "standard" (zero cost)
# For production:   use shield_tier = "advanced" (DDoS response team access)
################################################################################

################################################################################
# Shield Advanced Protections (only when shield_tier = "advanced")
################################################################################

resource "aws_shield_protection" "cloudfront" {
  count = var.shield_tier == "advanced" ? 1 : 0

  name         = "${var.project_name}-${var.environment}-cloudfront-shield"
  resource_arn = var.cloudfront_distribution_arn

  tags = var.tags
}

resource "aws_shield_protection" "alb" {
  count = var.shield_tier == "advanced" ? 1 : 0

  name         = "${var.project_name}-${var.environment}-alb-shield"
  resource_arn = var.alb_arn

  tags = var.tags
}

resource "aws_shield_protection" "route53" {
  count = var.shield_tier == "advanced" ? 1 : 0

  name         = "${var.project_name}-${var.environment}-route53-shield"
  resource_arn = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"

  tags = var.tags
}

################################################################################
# Shield Advanced Proactive Engagement (only when advanced + enabled)
################################################################################

resource "aws_shield_proactive_engagement" "main" {
  count = var.shield_tier == "advanced" && var.enable_proactive_engagement ? 1 : 0

  enabled = true

  dynamic "emergency_contact" {
    for_each = var.emergency_contacts
    content {
      contact_notes = emergency_contact.value.notes
      email_address = emergency_contact.value.email
      phone_number  = emergency_contact.value.phone
    }
  }
}
