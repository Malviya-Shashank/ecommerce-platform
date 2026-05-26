variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Maximum autoscaling storage in GB"
  type        = number
  default     = 500
}

variable "database_name" {
  description = "Default database name"
  type        = string
  default     = "ecommerce"
}

variable "master_username" {
  description = "Master username"
  type        = string
  default     = "dbadmin"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
}

variable "db_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "rds_security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "service_databases" {
  description = "List of service database names to create credentials for"
  type        = list(string)
  default = [
    "user-service",
    "product-service",
    "order-service",
    "payment-service",
    "notification-service"
  ]
}

variable "max_connections_alarm_threshold" {
  description = "Threshold for high connections alarm"
  type        = number
  default     = 200
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
