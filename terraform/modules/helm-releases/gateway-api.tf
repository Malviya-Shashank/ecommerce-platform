################################################################################
# Gateway API CRDs and Controller
################################################################################

resource "helm_release" "gateway_api_crds" {
  name       = "gateway-api"
  repository = "https://gateway-api-charts.sigs.k8s.io"
  chart      = "gateway-api"
  version    = var.gateway_api_version
  namespace  = "gateway-system"

  create_namespace = true

  depends_on = [var.eks_node_group_dependency]
}
