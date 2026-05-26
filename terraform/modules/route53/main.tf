################################################################################
# Route53 Module
################################################################################

################################################################################
# Hosted Zone (use existing or create new)
################################################################################

data "aws_route53_zone" "main" {
  count = var.create_zone ? 0 : 1
  name  = var.domain_name
}

resource "aws_route53_zone" "main" {
  count = var.create_zone ? 1 : 0
  name  = var.domain_name

  tags = merge(var.tags, {
    Name = var.domain_name
  })
}

locals {
  zone_id = var.create_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.main[0].zone_id
}

################################################################################
# DNS Records - All point to CloudFront
################################################################################

# API endpoint
resource "aws_route53_record" "api" {
  zone_id = local.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# ArgoCD
resource "aws_route53_record" "argocd" {
  zone_id = local.zone_id
  name    = "argocd.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# Grafana
resource "aws_route53_record" "grafana" {
  zone_id = local.zone_id
  name    = "grafana.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

################################################################################
# ACM Certificate Validation Records
################################################################################

resource "aws_route53_record" "acm_validation" {
  for_each = var.acm_domain_validation_options

  zone_id = local.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60

  allow_overwrite = true
}

################################################################################
# Health Check for ALB
################################################################################

resource "aws_route53_health_check" "alb" {
  count = var.enable_health_check ? 1 : 0

  fqdn              = var.alb_dns_name
  port               = 443
  type               = "HTTPS"
  resource_path      = "/healthz"
  failure_threshold  = 3
  request_interval   = 30

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-alb-health-check"
  })
}

################################################################################
# DNSSEC
################################################################################

resource "aws_route53_key_signing_key" "main" {
  count = var.enable_dnssec && var.create_zone ? 1 : 0

  hosted_zone_id             = local.zone_id
  key_management_service_arn = var.dnssec_kms_key_arn
  name                       = "${var.project_name}-${var.environment}-dnssec"
}

resource "aws_route53_hosted_zone_dnssec" "main" {
  count = var.enable_dnssec && var.create_zone ? 1 : 0

  hosted_zone_id = local.zone_id

  depends_on = [aws_route53_key_signing_key.main]
}
