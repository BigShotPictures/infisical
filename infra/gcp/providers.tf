provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Reads CLOUDFLARE_API_TOKEN from the environment — never put the token in
# .tf/.tfvars.
provider "cloudflare" {}
