# ─────────────────────────────────────────
# ARGOCD NAMESPACE
# ─────────────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]
}


# ─────────────────────────────────────────
# ARGOCD HELM INSTALL
# ─────────────────────────────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.3.11" # pin to a specific version for stability

  values = [
    <<-EOF
    server:
      service:
        type: LoadBalancer   # exposes ArgoCD UI externally
    EOF
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    aws_eks_node_group.main
  ]
}