# Memorystore for Redis has no AUTH password support — access is restricted
# by VPC isolation and firewall rules only (see google_compute_firewall in
# network.tf), not by a credential.
resource "google_redis_instance" "this" {
  name           = "infisical-redis"
  tier           = var.redis_tier
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region

  authorized_network = google_compute_network.this.id
  redis_version      = var.redis_version

  depends_on = [google_project_service.this]
}
