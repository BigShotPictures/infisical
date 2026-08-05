resource "google_container_cluster" "this" {
  name     = "infisical-cluster"
  location = var.region

  network    = google_compute_network.this.name
  subnetwork = google_compute_subnetwork.this.name

  # Node pool is managed separately below.
  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.gke_master_ipv4_cidr
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Required for the "gce" IngressClass (our k8s/ ingress + ManagedCertificate
  # setup) to work at all — without this, GLBC never reconciles Ingress
  # objects: no forwarding rules, no backend services, no error events,
  # just a permanently address-less Ingress.
  addons_config {
    http_load_balancing {
      disabled = false
    }
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  depends_on = [google_project_service.this]
}

resource "google_container_node_pool" "this" {
  name           = "infisical-node-pool"
  location       = var.region
  node_locations = var.gke_node_locations
  cluster        = google_container_cluster.this.name

  initial_node_count = var.gke_num_nodes_per_zone

  autoscaling {
    min_node_count = var.gke_min_nodes
    max_node_count = var.gke_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gke_machine_type
    disk_size_gb = 50

    # Matches the target_tags on google_compute_firewall.allow_health_checks.
    tags = ["gke-infisical"]

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

# Reserved for the GKE Ingress (gce ingress class) fronting Infisical.
resource "google_compute_global_address" "ingress" {
  name = "infisical-ip"
}
