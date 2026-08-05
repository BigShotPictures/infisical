# Generated once and stored in Secret Manager below — never typed by hand,
# never committed to state as plaintext in this repo. Losing ENCRYPTION_KEY
# makes existing encrypted secrets unrecoverable even with a DB restore, so
# back up its Secret Manager version out-of-band (see README.md).
resource "random_id" "encryption_key" {
  byte_length = 16
}

resource "random_id" "auth_secret" {
  byte_length = 32
}

locals {
  db_connection_uri = "postgresql://${google_sql_user.infisical.name}:${random_password.db_user.result}@${google_sql_database_instance.this.private_ip_address}:5432/${google_sql_database.infisical.name}"
  redis_url         = "redis://${google_redis_instance.this.host}:6379"

  secret_values = {
    infisical-encryption-key = random_id.encryption_key.hex
    infisical-auth-secret    = random_id.auth_secret.b64_std
    infisical-db-uri         = local.db_connection_uri
    infisical-redis-url      = local.redis_url
  }
}

resource "google_secret_manager_secret" "this" {
  for_each = local.secret_values

  secret_id = each.key
  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "this" {
  for_each = local.secret_values

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = each.value
}

# Workload Identity: the GSA that GKE pods impersonate to read the secrets
# above, bound to the Helm chart's Kubernetes service account.
resource "google_service_account" "gke_workload" {
  account_id   = "infisical-gsa"
  display_name = "Infisical GKE workload identity"
}

resource "google_secret_manager_secret_iam_member" "gke_workload_access" {
  for_each = google_secret_manager_secret.this

  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.gke_workload.email}"
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.gke_workload.name
  role               = "roles/iam.workloadIdentityUser"
  # Reads the pool off the cluster resource itself (not var.project_id
  # interpolation) so OpenTofu waits for the cluster's Workload Identity
  # pool to actually exist before creating this binding — the pool isn't
  # provisioned until google_container_cluster.this finishes.
  member = "serviceAccount:${google_container_cluster.this.workload_identity_config[0].workload_pool}[${var.k8s_namespace}/${var.k8s_service_account_name}]"
}
