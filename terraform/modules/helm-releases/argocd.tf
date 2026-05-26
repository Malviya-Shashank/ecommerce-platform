################################################################################
# ArgoCD - GitOps Continuous Delivery
################################################################################

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = "argocd"

  create_namespace = true
  timeout          = 600

  # Server configuration - ClusterIP (NOT LoadBalancer for cost savings)
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  # Run insecure mode (TLS terminated at ALB/CloudFront)
  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  # HA Mode
  set {
    name  = "controller.replicas"
    value = var.environment == "production" ? "2" : "1"
  }

  set {
    name  = "server.replicas"
    value = var.environment == "production" ? "2" : "1"
  }

  set {
    name  = "repoServer.replicas"
    value = var.environment == "production" ? "2" : "1"
  }

  # Redis HA
  set {
    name  = "redis-ha.enabled"
    value = var.environment == "production" ? "true" : "false"
  }

  set {
    name  = "redis.enabled"
    value = var.environment == "production" ? "false" : "true"
  }

  # Server resource limits
  set {
    name  = "server.resources.requests.cpu"
    value = "250m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }

  # Controller resource limits
  set {
    name  = "controller.resources.requests.cpu"
    value = "250m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "1Gi"
  }

  # Enable Prometheus metrics
  set {
    name  = "server.metrics.enabled"
    value = "true"
  }

  set {
    name  = "server.metrics.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.metrics.serviceMonitor.enabled"
    value = "true"
  }

  # Application Set Controller
  set {
    name  = "applicationSet.enabled"
    value = "true"
  }

  depends_on = [var.eks_node_group_dependency]
}
