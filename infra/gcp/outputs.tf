output "database_instance_connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance)."
  value       = google_sql_database_instance.this.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance."
  value       = google_sql_database_instance.this.private_ip_address
  sensitive   = true
}

output "gke_cluster_name" {
  description = "Name of the GKE cluster, for `gcloud container clusters get-credentials`."
  value       = google_container_cluster.this.name
}

output "gke_workload_service_account_email" {
  description = "Email of the GSA bound to the Helm chart's Kubernetes service account via Workload Identity."
  value       = google_service_account.gke_workload.email
}

output "redis_host" {
  description = "Private IP address of the Memorystore Redis instance."
  value       = google_redis_instance.this.host
  sensitive   = true
}

output "secret_manager_secret_ids" {
  description = "Secret Manager secret IDs holding ENCRYPTION_KEY, AUTH_SECRET, the DB connection URI, and the Redis URL — reference these from the Helm values (envFrom / Secret Manager CSI driver), don't read the values back into this output."
  value       = { for k, v in google_secret_manager_secret.this : k => v.secret_id }
}

output "static_ip_address" {
  description = "Reserved global static IP for the GKE Ingress. Point the domain's DNS A record at this address."
  value       = google_compute_global_address.ingress.address
}

output "vpc_name" {
  description = "Name of the VPC network."
  value       = google_compute_network.this.name
}
