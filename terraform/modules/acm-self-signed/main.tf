################################################################################
# Self-Signed TLS Certificate for Dev Environment
#
# This module generates a self-signed certificate and imports it into ACM.
# Used for dev environments where Route53/DNS validation is not available
# (e.g., sslip.io free domains).
#
# Cost: $0 (ACM imported certificates are free)
# Trade-off: Browser shows "Not Secure" warning (self-signed)
# Benefit: Full TLS architecture exposure for learning
################################################################################

# Generate a private key
resource "tls_private_key" "self_signed" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate a self-signed certificate
resource "tls_self_signed_cert" "self_signed" {
  private_key_pem = tls_private_key.self_signed.private_key_pem

  subject {
    common_name         = "*.sslip.io"
    organization        = "${var.project_name}-${var.environment}"
    organizational_unit = "DevOps"
  }

  # Valid for 1 year
  validity_period_hours = 8760

  # Wildcard SANs for sslip.io
  dns_names = [
    "*.sslip.io",
    "sslip.io",
  ]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Import the self-signed certificate into ACM
resource "aws_acm_certificate" "self_signed" {
  private_key      = tls_private_key.self_signed.private_key_pem
  certificate_body = tls_self_signed_cert.self_signed.cert_pem

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}-self-signed-cert"
    CertType    = "self-signed"
    Environment = var.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}
