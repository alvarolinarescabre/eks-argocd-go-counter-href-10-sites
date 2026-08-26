resource "kubectl_manifest" "kgateway_crds" {
  for_each  = data.kubectl_file_documents.kgateway_crds.manifests
  yaml_body = each.value

  depends_on = [module.eks]
}

resource "kubectl_manifest" "kgateway_helm_cdrs" {
  yaml_body = file("${path.root}/argocd/kgateway/crds-helm.yaml")

  depends_on = [kubectl_manifest.kgateway_crds]
}

resource "kubectl_manifest" "kgateway_helm" {
  yaml_body = file("${path.root}/argocd/kgateway/helm.yaml")

  depends_on = [kubectl_manifest.kgateway_helm_cdrs]
}