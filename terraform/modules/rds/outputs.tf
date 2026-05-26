output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  description = "RDS instance hostname"
  value       = aws_db_instance.main.address
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret for master credentials"
  value       = aws_secretsmanager_secret.rds_master.arn
}

output "service_secret_arns" {
  description = "Map of service name to Secrets Manager secret ARN"
  value       = { for k, v in aws_secretsmanager_secret.service_db : k => v.arn }
}

output "kms_key_arn" {
  description = "KMS key ARN used for RDS encryption"
  value       = aws_kms_key.rds.arn
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}
