resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  namespace        = var.argocd_namespace
  create_namespace = true

  wait    = true
  timeout = 600

  values = [yamlencode({
    configs = {
      params = {
        "server.insecure" = true
      }
    }
    redis-ha       = { enabled = false }
    controller     = { replicas = 1 }
    server         = { replicas = 1 }
    repoServer     = { replicas = 1 }
    applicationSet = { replicas = 1 }
  })]
}