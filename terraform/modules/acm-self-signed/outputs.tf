output "certificate_arn" {
  description = "ACM certificate ARN (self-signed, imported)"
  value       = aws_acm_certificate.self_signed.arn
}

output "certificate_domain" {
  description = "Certificate common name"
  value       = tls_self_signed_cert.self_signed.subject[0].common_name
}

output "certificate_expiry" {
  description = "Certificate expiration date"
  value       = tls_self_signed_cert.self_signed.validity_end_time
}
