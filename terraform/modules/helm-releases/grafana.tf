################################################################################
# Grafana - Observability Dashboard
# Accessed via Gateway API (ClusterIP, NOT LoadBalancer)
################################################################################

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = var.grafana_version
  namespace  = "monitoring"

  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      # ClusterIP — accessed via Gateway API HTTPRoute, NOT LoadBalancer
      service = {
        type = "ClusterIP"
        port = 3000
      }

      replicas = var.environment == "production" ? 2 : 1

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
        enabled          = true
        type             = "pvc"
        size             = "10Gi"
        storageClassName = "gp3"
      }

      adminPassword = var.grafana_admin_password

      # Pre-configured data sources
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "Prometheus"
              type      = "prometheus"
              url       = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
              access    = "proxy"
              isDefault = true
            },
            {
              name   = "Loki"
              type   = "loki"
              url    = "http://loki.monitoring.svc.cluster.local:3100"
              access = "proxy"
            }
          ]
        }
      }

      # Pre-provisioned dashboards
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [
            {
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options = {
                path = "/var/lib/grafana/dashboards/default"
              }
            }
          ]
        }
      }

      dashboards = {
        default = {
          kubernetes-cluster = {
            gnetId     = 315
            revision   = 3
            datasource = "Prometheus"
          }
          node-exporter = {
            gnetId     = 1860
            revision   = 37
            datasource = "Prometheus"
          }
          kubernetes-pods = {
            gnetId     = 6417
            revision   = 1
            datasource = "Prometheus"
          }
        }
      }

      # Grafana.ini config
      "grafana.ini" = {
        server = {
          root_url = "https://grafana.${var.domain_name}"
        }
        security = {
          allow_embedding = true
        }
        auth = {
          disable_login_form = false
        }
      }
    })
  ]

  depends_on = [helm_release.prometheus, var.eks_node_group_dependency]
}
