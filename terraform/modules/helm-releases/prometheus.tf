################################################################################
# Prometheus Stack (kube-prometheus-stack)
################################################################################

resource "helm_release" "prometheus" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_version
  namespace  = "monitoring"

  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention         = "15d"
          retentionSize     = "40GB"
          replicas          = var.environment == "production" ? 2 : 1
          resources = {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "1"
              memory = "4Gi"
            }
          }
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          replicas = var.environment == "production" ? 2 : 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }

      grafana = {
        enabled = false # We deploy Grafana separately for better control
      }

      # Node exporter for node metrics
      nodeExporter = {
        enabled = true
      }

      # Kube-state-metrics
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [var.eks_node_group_dependency]
}
