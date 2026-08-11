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

locals {
  # Only the 4 keys below — merge-patched, not a full replace, so SITE_URL
  # and the SMTP_* keys added by hand (DEPLOYMENT.md Step 6) are untouched.
  k8s_secret_patch = jsonencode({
    stringData = {
      ENCRYPTION_KEY    = random_id.encryption_key.hex
      AUTH_SECRET       = random_id.auth_secret.b64_std
      DB_CONNECTION_URI = local.db_connection_uri
      REDIS_URL         = local.redis_url
    }
  })
}

# Bridges Secret Manager (above) to the native k8s Secret the
# infisical-standalone Helm chart actually reads (kubeSecretRef in
# k8s/infisical-values.yaml) — without this, Terraform has no visibility
# into that Secret at all, so rotating a value here (e.g. replacing the
# Redis instance, which changes its host) silently goes stale in the
# cluster until someone remembers to re-run DEPLOYMENT.md Step 5 by hand.
# That exact gap caused a live outage on 2026-08-11: a Redis tier change
# replaced the instance, and the stale REDIS_URL in the cluster left both
# Infisical pods crash-looping on ETIMEDOUT until it was patched manually.
#
# Requires kubectl already pointed at the cluster (DEPLOYMENT.md Step 4)
# at apply time — the `|| echo "WARNING..."` below keeps that requirement
# from hard-failing the whole apply (expected on the very first apply,
# before Step 5 has even created the namespace/Secret yet), but still
# prints a visible warning instead of failing silently, since a wrong
# kubectl context on a LATER apply would otherwise reintroduce the same
# silent-staleness bug this exists to prevent.
resource "null_resource" "sync_k8s_secret" {
  triggers = {
    patch = local.k8s_secret_patch
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl patch secret infisical-secrets -n ${var.k8s_namespace} --type=merge -p '${local.k8s_secret_patch}' \
        || echo "WARNING: kubectl patch failed. Expected only on the very first apply, before Step 5 creates the Secret. If this is NOT the first apply, infisical-secrets is now stale — check your kubectl context and re-run DEPLOYMENT.md Step 5 by hand."
      kubectl rollout restart deployment/${var.k8s_deployment_name} -n ${var.k8s_namespace} \
        || echo "WARNING: kubectl rollout restart failed. Expected only before the Helm install (Step 7) has run once. If Infisical is already installed, its pods are still running with the OLD secret values — restart the deployment by hand."
    EOT
  }

  depends_on = [google_secret_manager_secret_version.this]
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
