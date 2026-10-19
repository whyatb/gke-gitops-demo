locals {
  image_repository = "${google_artifact_registry_repository.apps.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.apps.repository_id}/hello-api"
}

output "get_credentials_command" {
  description = "Configures kubectl to talk to the cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --zone ${var.zone} --project ${var.project_id}"
}

output "image_repository" {
  description = "Where CI pushes hello-api images."
  value       = local.image_repository
}

output "github_actions_variables" {
  description = "Repository variables the app workflow reads (GitHub: Settings > Secrets and variables > Actions > Variables). None of these are secret."
  value = {
    GCP_WIF_PROVIDER       = google_iam_workload_identity_pool_provider.github.name
    GCP_CI_SERVICE_ACCOUNT = google_service_account.github_ci.email
    IMAGE_REPOSITORY       = local.image_repository
  }
}
