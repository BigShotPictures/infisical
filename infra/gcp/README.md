# Infisical on GCP (GKE + Cloud SQL + Memorystore) — OpenTofu

This OpenTofu config sets up the infrastructure in
[`docs/self-hosting/deployment-options/gcp-native.mdx`](../../docs/self-hosting/deployment-options/gcp-native.mdx).

It creates:

- A VPC-native GKE cluster
- A Cloud SQL instance for PostgreSQL
- A Memorystore instance for Redis
- Secret Manager secrets for Infisical
- A Workload Identity binding, so Infisical's pods can read those secrets

This config does not install Infisical. The Helm chart step in the docs
does that. See "What this config does not do" below.

For the full, ordered runbook for the `bsp-infisical` deployment — billing
setup, the state bucket, `tofu apply`, the Helm install, the managed
certificate, and the first admin account — see
[`DEPLOYMENT.md`](DEPLOYMENT.md). This README explains what the OpenTofu
config itself does; `DEPLOYMENT.md` is the step-by-step guide that also
covers the parts outside OpenTofu.

The variables in `variables.tf` use the docs' **minimum-spec** values by
default: `e2-small` nodes, `db-f1-micro`, 1 GB of Redis, 1 node per zone.
These keep the first `tofu plan` cheap to run. For a production
deployment, set `gke_machine_type`, `db_tier`, `redis_memory_size_gb`, and
`gke_num_nodes_per_zone` to the docs' "Recommended (Production)" values.

## Prerequisites

- `gcloud`, signed in (`gcloud auth login`), pointed at a project with
  billing enabled
- [OpenTofu](https://opentofu.org/docs/intro/install/) 1.7 or later
  (`brew install opentofu`)
- `kubectl` and `helm`, for the Helm install step later (not part of this
  config)
- If `manage_dns = true` (the default): a `CLOUDFLARE_API_TOKEN` env var
  with DNS edit rights on the zone, and the zone's ID
  (`var.cloudflare_zone_id`). See "DNS" below. Set `manage_dns = false` if
  you manage DNS somewhere else.

## Step 1: Create the state bucket

OpenTofu stores its state in a GCS bucket. This config cannot create that
bucket itself, because it needs the bucket to exist first. Create it by
hand, once:

```bash
gcloud storage buckets create gs://<your-bucket-name> \
  --project=<your-gcp-project-id> \
  --location=<region> \
  --uniform-bucket-level-access
gcloud storage buckets update gs://<your-bucket-name> --versioning
```

Then create a file named `terraform.gcs.tfbackend` in this directory:

```hcl
bucket = "<your-bucket-name>"
prefix = "infisical"
```

This file is specific to your bucket, so `.gitignore` excludes it from
git.

## Step 2: Plan

```bash
tofu init -backend-config=terraform.gcs.tfbackend
tofu fmt -recursive
tofu validate
tofu plan -var="project_id=<your-gcp-project-id>" -var="domain=infisical.example.com"
```

Read the plan output before you do anything else. **Do not run `tofu
apply` until you have reviewed the plan.** This config creates real GCP
resources that cost money. The Cloud SQL instance and the GKE cluster are
the most expensive ones.

Instead of repeating `-var` flags, put your values in a `.tfvars` file:

```hcl
# terraform.tfvars
project_id = "<your-gcp-project-id>"
domain     = "infisical.example.com"
```

## Step 3: After `tofu apply`

1. Get cluster credentials:
   ```bash
   gcloud container clusters get-credentials $(tofu output -raw gke_cluster_name) --region <region>
   ```
2. Go to "Deploy Infisical using Helm" in
   [`gcp-native.mdx`](../../docs/self-hosting/deployment-options/gcp-native.mdx#deploy-infisical-using-helm).
   Use these values from `tofu output`:
   - `serviceAccount.annotations["iam.gke.io/gcp-service-account"]` — use
     `gke_workload_service_account_email`
   - `envFrom` secret reference — point it at the Secret Manager secrets
     listed in `secret_manager_secret_ids`. Read them in through the
     Secret Manager CSI driver, or copy them into a Kubernetes Secret (see
     the docs' "Kubernetes Secrets" tab).
   - Ingress static IP name — `infisical-ip`. Use
     `static_ip_address` for the address itself.
3. Point DNS at the static IP.
   - If `manage_dns = false`: create the A record yourself, using `tofu
     output -raw static_ip_address`.
   - If `manage_dns = true`: this config already created the Cloudflare A
     record. See "DNS" below.
4. Apply the `ManagedCertificate` and `FrontendConfig` YAML from the docs'
   "Configure HTTPS access with SSL/TLS" step, using `kubectl`. These are
   Kubernetes objects, not GCP resources, so OpenTofu does not manage
   them.

## What this config does not do

- Install Infisical. That is the Helm chart step above. A filled-in values
  file for this deployment lives at
  [`k8s/infisical-values.yaml`](k8s/infisical-values.yaml).
- Manage the `ManagedCertificate`, `FrontendConfig`, or `Ingress`
  Kubernetes objects. Apply those with `kubectl`, per the docs. Templates
  for this deployment live at
  [`k8s/managed-cert.yaml`](k8s/managed-cert.yaml) and
  [`k8s/frontend-config.yaml`](k8s/frontend-config.yaml).
- Set up SMTP or monitoring alerts. The docs cover these as separate,
  optional steps. `DEPLOYMENT.md` covers them for this deployment.

The docs' own Terraform example calls out missing Secret Manager and IAM
wiring. This config adds that wiring (see `secrets.tf`), so it goes further
than a plain copy of the docs' example.

## DNS

By default (`manage_dns = true`), this config creates a Cloudflare A
record for `domain`. The record points at the reserved ingress static IP
(`google_compute_global_address.ingress`).

This config does not create the Cloudflare zone itself. The zone is a
shared, one-time resource, not something each app's infra should create or
compete over. To use it:

1. Find the zone ID. Check the Cloudflare dashboard, or run:
   ```bash
   curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
     "https://api.cloudflare.com/client/v4/zones?name=<root-domain>"
   ```
2. Set `cloudflare_zone_id` to that ID.
3. Create a scoped API token: Cloudflare dashboard → My Profile → API
   Tokens → Create Token → "Edit zone DNS" template, scoped to the
   `bigshotpictures.ai` zone only. Do not reuse a `wrangler login` OAuth
   token here — it has no DNS scope (only `account:read`, `user:read`, and
   Workers script/KV/route/tail permissions), so this config would just
   fail with a permissions error. Confirm what a token can do with
   `wrangler whoami`.
4. Export that token as `CLOUDFLARE_API_TOKEN` before you run `tofu plan`
   or `tofu apply`.

The record uses `proxied = false` on purpose. The GKE Ingress's
Google-managed certificate checks and terminates TLS directly against this
IP. If Cloudflare proxies the record, a different IP sits in front, and
certificate issuance and renewal break.

`terraform.tfvars` in this directory already sets `project_id =
"bsp-infisical"`, `domain = "infisical.bigshotpictures.ai"`, and
`cloudflare_zone_id` (looked up from the live `bigshotpictures.ai` zone).
This file is gitignored, so it stays local. You still need to export
`CLOUDFLARE_API_TOKEN` yourself, per step 3 above, before the first `tofu
plan`.

## Secrets

OpenTofu generates `ENCRYPTION_KEY` and `AUTH_SECRET` itself, using
`random_id` in `secrets.tf`. It stores them in Secret Manager and in this
config's state file. It never prints them to a terminal. This has two
consequences:

- **Restrict who can read the GCS state bucket.** The state file holds
  these values in plain text, like any Terraform or OpenTofu state that
  includes secrets.
- **Back up `ENCRYPTION_KEY` outside GCP too.**
  ```bash
  gcloud secrets versions access latest --secret=infisical-encryption-key
  ```
  Without this key, you cannot recover encrypted secrets, even from a full
  database restore.

## Design notes

- This config uses one environment. It does not split into `modules/` and
  `environments/{staging,prod}`. It is a self-hosting reference, not a Big
  Shot Pictures app with its own staging and prod pipeline, so there is no
  fixed set of environments to model. (It is also now BSP's actual config
  for the `bsp-infisical` GCP project — see `terraform.tfvars` — but it is
  still one environment.)
- This config wires up Cloudflare DNS directly, in `dns.tf`, instead of
  leaving it as a manual step. BSP's `bigshotpictures.ai` zone already
  exists in Cloudflare. Set `manage_dns = false` if you fork this config
  without a Cloudflare zone to point at.
- `region` defaults to `us-west1` (Oregon), BSP's standard region across
  clouds. Override it if you fork this config outside BSP and want a
  different region.
- This config has no GitHub Actions workflow and no Workload Identity
  Federation for CI. It is not a deploy pipeline for one fixed Infisical
  instance, so there is no CI identity to set up. The Workload Identity
  binding that does exist, in `secrets.tf`, connects pods to GCP (GKE
  Workload Identity). That is a different mechanism from CI-to-GCP (WIF),
  and Infisical's pods need it to read their own secrets.
