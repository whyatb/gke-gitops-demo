provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "current" {}

# Helm installs Argo CD into the cluster created below, authenticating with the
# same Google credentials Terraform is running as.
provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.main.endpoint}"
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  }
}
