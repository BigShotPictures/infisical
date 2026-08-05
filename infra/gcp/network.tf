# VPC-native network hosting the GKE cluster, Cloud SQL instance, and
# Memorystore instance.
resource "google_compute_network" "this" {
  name                    = "infisical-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name                     = "infisical-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.this.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_secondary_range_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_secondary_range_cidr
  }
}

# Cloud Router + Cloud NAT give the private GKE nodes outbound internet
# access (pulling images, calling external APIs) without public IPs.
resource "google_compute_router" "this" {
  name    = "infisical-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  name                               = "infisical-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks"
  network = google_compute_network.this.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  # GCP's load balancer health check ranges.
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gke-infisical"]
}

# Reserved range + peering connection Cloud SQL and Memorystore attach to for
# private (non-public-IP) connectivity from the VPC.
resource "google_compute_global_address" "private_service_access" {
  name          = "google-managed-services-infisical-vpc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_service_range_prefix_length
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]
}
