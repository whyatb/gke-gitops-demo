resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  values           = [file("${path.module}/values/argocd.yaml")]

  # Argo CD's pods pull images from the internet and need nodes to run on.
  depends_on = [
    google_container_node_pool.primary,
    google_compute_router_nat.nat,
  ]
}

# The only Argo CD Application Terraform creates. It points Argo CD at the
# argocd/ directory of the repository, and everything else Argo CD manages
# (projects, applications) is defined there, in Git. This is the "app of apps"
# pattern: after this bootstrap, adding a service is a Git commit, not a
# Terraform change.
resource "helm_release" "argocd_root_app" {
  name       = "argocd-root-app"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = "https://github.com/${var.github_repository}.git"
          targetRevision = "main"
          path           = "argocd"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
