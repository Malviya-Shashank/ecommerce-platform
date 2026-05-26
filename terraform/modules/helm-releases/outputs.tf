output "loki_s3_bucket_arn" {
  description = "ARN of the Loki S3 bucket"
  value       = aws_s3_bucket.loki.arn
}

output "loki_s3_bucket_id" {
  description = "ID of the Loki S3 bucket"
  value       = aws_s3_bucket.loki.id
}
