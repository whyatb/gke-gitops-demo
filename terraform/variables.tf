variable "project_id" {
  description = "Google Cloud project to deploy into."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in owner/name form, with exact capitalization. Only this repository's main branch may push images, and Argo CD deploys from it."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "Use the owner/name form, for example octocat/gke-gitops-demo."
  }
}

variable "region" {
  description = "Region for the network and the Artifact Registry repository."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for the cluster. A zonal cluster is cheaper than a regional one, and GKE's free tier covers the management fee for one zonal cluster per billing account."
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "gitops-demo"
}

variable "machine_type" {
  description = "Machine type for cluster nodes."
  type        = string
  default     = "e2-standard-2"
}

variable "max_nodes" {
  description = "Upper bound for the node pool autoscaler."
  type        = number
  default     = 3
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart."
  type        = string
  default     = "10.10.5"
}

variable "argocd_apps_chart_version" {
  description = "Version of the argocd-apps Helm chart."
  type        = string
  default     = "2.0.6"
}
