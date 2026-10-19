resource "google_compute_network" "main" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "gke" {
  name    = "${var.cluster_name}-nodes"
  region  = var.region
  network = google_compute_network.main.id

  ip_cidr_range = "10.10.0.0/20"

  # Lets nodes without public IPs reach Google APIs such as Artifact Registry.
  private_ip_google_access = true

  # GKE gives pods and Services their own IP ranges within the subnet.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# Nodes have private IPs only. Cloud NAT gives them outbound internet access,
# which Argo CD needs to pull from GitHub and the cluster needs to pull
# third-party images, without exposing the nodes to inbound traffic.
resource "google_compute_router" "nat" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
