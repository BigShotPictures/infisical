variable "backup_retained_count" {
  type        = number
  description = "Number of automated Cloud SQL backups to retain."
  default     = 7
}

variable "backup_start_time" {
  type        = string
  description = "Daily start time (HH:MM, UTC) for the Cloud SQL automated backup window."
  default     = "03:00"
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID owning `domain`'s parent zone (e.g. the bigshotpictures.ai zone ID). Required when manage_dns is true. The zone itself is a one-time, workspace-level Cloudflare resource — this config only references it by ID, it never creates or manages the zone."
  default     = null
}

variable "db_disk_size_gb" {
  type        = number
  description = "Initial storage size, in GB, for the Cloud SQL instance. Auto-increases as needed."
  default     = 20
}

variable "db_tier" {
  type        = string
  description = "Machine tier for the Cloud SQL instance. Defaults to the docs' minimum-spec tier (db-f1-micro); use db-n1-standard-2 or larger for production."
  default     = "db-f1-micro"
}

variable "db_version" {
  type        = string
  description = "Cloud SQL PostgreSQL version."
  default     = "POSTGRES_15"
}

variable "domain" {
  type        = string
  description = "Public domain Infisical will be served on, e.g. infisical.example.com. Used for the ManagedCertificate and as a name tag on the reserved static IP."
}

variable "gke_machine_type" {
  type        = string
  description = "GCE machine type for GKE nodes. Defaults to the docs' minimum-spec type (e2-small); use n2-standard-2 or larger for production."
  default     = "e2-small"
}

variable "gke_master_ipv4_cidr" {
  type        = string
  description = "/28 CIDR range for the private GKE control plane."
  default     = "172.16.0.0/28"
}

variable "gke_max_nodes" {
  type        = number
  description = "Maximum node count the GKE cluster autoscaler may scale up to."
  default     = 5
}

variable "gke_min_nodes" {
  type        = number
  description = "Minimum node count the GKE cluster autoscaler may scale down to."
  default     = 1
}

variable "gke_node_locations" {
  type        = list(string)
  description = "Zones within `region` the GKE node pool's instances land in. Defaults to us-west1-a and us-west1-b only, excluding us-west1-c, which hit a persistent GCE_STOCKOUT across multiple apply attempts on 2026-07-30. Widen back to all three zones once that clears."
  default     = ["us-west1-a", "us-west1-b"]
}

variable "gke_num_nodes_per_zone" {
  type        = number
  description = "Initial number of nodes per zone in the GKE node pool. Defaults to the docs' minimum spec (1); use 2+ for production."
  default     = 1
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace the Infisical Helm release is installed into. Used to build the Workload Identity binding member string."
  default     = "infisical"
}

variable "k8s_service_account_name" {
  type        = string
  description = "Kubernetes service account name the infisical-standalone Helm chart creates: \"<helm release name>-infisical\" when infisical.serviceAccount.create is true. Our release name is \"infisical\", so this is \"infisical-infisical\", not just \"infisical\". Used to build the Workload Identity binding member string."
  default     = "infisical-infisical"
}

variable "manage_dns" {
  type        = bool
  description = "Whether to create a Cloudflare DNS record for `domain` pointing at the reserved ingress static IP. Set false if you manage DNS elsewhere (Route53, a registrar, etc.) — the static IP output still tells you what to point at manually."
  default     = true
}

variable "pods_secondary_range_cidr" {
  type        = string
  description = "Secondary IP range for GKE pods (VPC-native cluster)."
  default     = "10.4.0.0/14"
}

variable "private_service_range_prefix_length" {
  type        = number
  description = "Prefix length of the global address range reserved for private services access (Cloud SQL VPC peering)."
  default     = 16
}

variable "project_id" {
  type        = string
  description = "GCP project ID that hosts the VPC, GKE cluster, Cloud SQL instance, and Memorystore instance."
}

variable "redis_memory_size_gb" {
  type        = number
  description = "Memorystore Redis instance capacity, in GB. Defaults to the docs' minimum spec (1 GB); use 2 GB or larger for production."
  default     = 1
}

variable "redis_tier" {
  type        = string
  description = "Memorystore service tier. STANDARD_HA enables cross-zone replication and automatic failover."
  default     = "STANDARD_HA"
}

variable "redis_version" {
  type        = string
  description = "Memorystore Redis version."
  default     = "REDIS_7_0"
}

variable "region" {
  type        = string
  description = "GCP region for all regional resources (GKE cluster, Cloud SQL, Memorystore, subnet). Defaults to us-west1 (Oregon), BSP's standard region across clouds."
  default     = "us-west1"
}

variable "services_secondary_range_cidr" {
  type        = string
  description = "Secondary IP range for GKE services (VPC-native cluster)."
  default     = "10.8.0.0/20"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary IP range for the GKE node subnet."
  default     = "10.0.0.0/20"
}
