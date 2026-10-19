# Nodes run as a dedicated service account with only the permissions GKE nodes
# need, instead of the broad Compute Engine default service account.
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-nodes"
  display_name = "GKE nodes"

  depends_on = [google_project_service.enabled]
}

resource "google_project_iam_member" "gke_nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.gke_nodes.member
}

resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.zone

  network    = google_compute_network.main.id
  subnetwork = google_compute_subnetwork.gke.id

  # The node pool is managed as its own resource (below) so it can change
  # without recreating the cluster. GKE insists on a default pool at creation,
  # so create a minimal one and delete it straight away.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  release_channel {
    channel = "REGULAR"
  }

  # Dataplane V2 (eBPF) is what enforces Kubernetes NetworkPolicies.
  datapath_provider = "ADVANCED_DATAPATH"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Nodes get private IPs only. The control plane keeps a public endpoint so
  # Terraform and kubectl can reach it; it still requires Google IAM auth.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  # Lets pods authenticate to Google APIs as an IAM service account, without
  # key files. Not used by hello-api today, but it's the safe default.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Allows `terraform destroy` for this demo. Leave this true for real clusters.
  deletion_protection = false

  depends_on = [
    google_project_service.enabled,
    google_project_iam_member.gke_nodes,
  ]
}

resource "google_container_node_pool" "primary" {
  name     = "primary"
  cluster  = google_container_cluster.main.id
  location = var.zone

  initial_node_count = 1
  autoscaling {
    min_node_count = 1
    max_node_count = var.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    disk_type    = "pd-balanced"
    disk_size_gb = 50

    # Access is limited by the service account's IAM roles; the broad scope
    # just avoids a second, legacy permission layer.
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Pods see the GKE metadata server, not the node's credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
