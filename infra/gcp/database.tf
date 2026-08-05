resource "google_sql_database_instance" "this" {
  name             = "infisical-db"
  database_version = var.db_version
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.db_disk_size_gb
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.this.id
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.backup_retained_count
    }
  }

  deletion_protection = true

  depends_on = [google_service_networking_connection.private_service_access]
}

resource "google_sql_database" "infisical" {
  name     = "infisical"
  instance = google_sql_database_instance.this.name
}

# Random, not user-supplied: rotating this only requires `tofu apply` plus an
# app restart, and it never needs to be typed in by hand.
resource "random_password" "postgres_root" {
  length  = 32
  special = false
}

resource "google_sql_user" "postgres_root" {
  name     = "postgres"
  instance = google_sql_database_instance.this.name
  password = random_password.postgres_root.result
}

resource "random_password" "db_user" {
  length  = 32
  special = false
}

resource "google_sql_user" "infisical" {
  name     = "infisical_user"
  instance = google_sql_database_instance.this.name
  password = random_password.db_user.result
}
