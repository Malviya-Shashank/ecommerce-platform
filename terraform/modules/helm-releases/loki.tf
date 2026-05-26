################################################################################
# Loki - Log Aggregation (S3-backed for cost efficiency)
################################################################################

resource "aws_s3_bucket" "loki" {
  bucket = "${var.project_name}-${var.environment}-loki-logs"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-loki-logs"
  })
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "loki-log-lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_version
  namespace  = "monitoring"

  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false

        storage = {
          type = "s3"
          s3 = {
            region     = var.aws_region
            bucketnames = aws_s3_bucket.loki.id
          }
        }

        commonConfig = {
          replication_factor = 1
        }

        schemaConfig = {
          configs = [
            {
              from = "2024-01-01"
              store = "tsdb"
              object_store = "s3"
              schema = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }

        limits_config = {
          retention_period         = "720h" # 30 days
          max_query_length         = "721h"
          max_query_parallelism    = 32
          ingestion_rate_mb        = 10
          ingestion_burst_size_mb  = 20
        }
      }

      singleBinary = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "200m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
        persistence = {
          enabled      = true
          size         = "10Gi"
          storageClass = "gp3"
        }
      }

      serviceAccount = {
        create = true
        name   = "loki"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.loki_role_arn
        }
      }

      gateway = {
        enabled = false
      }

      # Disable unused components
      backend  = { replicas = 0 }
      read     = { replicas = 0 }
      write    = { replicas = 0 }

      test = {
        enabled = false
      }
    })
  ]

  depends_on = [var.eks_node_group_dependency]
}

################################################################################
# Promtail - Log Collector (DaemonSet)
################################################################################

resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_version
  namespace  = "monitoring"

  values = [
    yamlencode({
      config = {
        clients = [
          {
            url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
          }
        ]
      }

      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }

      tolerations = [
        {
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [helm_release.loki]
}
