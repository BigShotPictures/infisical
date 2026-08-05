# Deploy Infisical for Big Shot Pictures

This guide gives the exact steps to deploy Infisical on GCP for Big Shot
Pictures. It uses the OpenTofu config in this folder and the Kubernetes
files in `k8s/`.

Facts about this deployment:

- GCP project: `bsp-infisical`
- Domain: `infisical.bigshotpictures.ai`
- DNS provider: Cloudflare
- Region: `us-west1` (Oregon — BSP's standard region across clouds)

This guide follows the general steps in
[`docs/self-hosting/deployment-options/gcp-native.mdx`](../../docs/self-hosting/deployment-options/gcp-native.mdx).
Read `README.md` in this folder first. It explains what the OpenTofu config
does and does not manage.

## Before you start

Check these items before you run any command.

### 1. Billing is not yet enabled

The `bsp-infisical` project has no billing account linked yet. You must fix
this before OpenTofu can enable APIs or create resources.

1. List your billing accounts:
   ```bash
   gcloud billing accounts list
   ```
2. Link one to the project:
   ```bash
   gcloud billing projects link bsp-infisical --billing-account=<BILLING_ACCOUNT_ID>
   ```
3. Confirm the link:
   ```bash
   gcloud billing projects describe bsp-infisical
   ```
   The output must show `billingEnabled: true`.

### 2. Set your active gcloud project

Your gcloud CLI defaults to a different project. Point it at
`bsp-infisical` for this work:

```bash
gcloud config set project bsp-infisical
```

### 3. Install Helm

Helm is not installed on this machine. Install it with Homebrew:

```bash
brew install helm
```

`gcloud`, `kubectl`, and `tofu` (OpenTofu) are already installed. Confirm
their versions if you have not used them recently:

```bash
gcloud version
kubectl version --client
tofu version
```

### 4. Get a Cloudflare API token

The OpenTofu config creates the DNS record for `infisical.bigshotpictures.ai`
through the Cloudflare API. Create a token with **Zone → DNS → Edit**
permission, scoped to the `bigshotpictures.ai` zone, in the Cloudflare
dashboard under **My Profile → API Tokens**.

Export it in your shell before you run any `tofu` command:

```bash
export CLOUDFLARE_API_TOKEN=<your-token>
```

Do not put this token in a file in this repo.

## Step 1: Create the OpenTofu state bucket

The state bucket cannot be created by the config that uses it. Create it
once, by hand:

```bash
gcloud storage buckets create gs://bsp-infisical-tofu-state \
  --project=bsp-infisical \
  --location=us-west1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://bsp-infisical-tofu-state --versioning
```

Create `terraform.gcs.tfbackend` in this folder (`infra/gcp/`). This file is
gitignored, so it stays local to your machine:

```hcl
bucket = "bsp-infisical-tofu-state"
prefix = "infisical"
```

## Step 2: Confirm the Cloudflare zone ID

`terraform.tfvars` in this folder already sets `project_id`, `domain`,
`region`, and `cloudflare_zone_id`. The zone ID
(`bb99848f2022831d4ed34ea64331f7fa`) was looked up once and saved — you do
not need to look it up again.

Confirm it still matches the live `bigshotpictures.ai` zone before you
apply, since a stale or wrong zone ID fails at `tofu apply` with a
Cloudflare 403, not at `tofu plan`:

```bash
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/bb99848f2022831d4ed34ea64331f7fa" \
  | jq -r '.result.name'
```

This must print `bigshotpictures.ai`. If it does not, or the request
fails, re-run the lookup and update `cloudflare_zone_id` in
`terraform.tfvars`:

```bash
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones?name=bigshotpictures.ai" \
  | jq -r '.result[0].id'
```

<Note>
A `wrangler login` OAuth token cannot run either `curl` above — it has no
DNS/zone scope (confirm with `wrangler whoami`). You need a separate,
scoped Cloudflare API token for this (see "Get a Cloudflare API token"
above).
</Note>

## Step 3: Review and apply the OpenTofu plan

```bash
tofu init -backend-config=terraform.gcs.tfbackend
tofu validate
tofu plan
```

`tofu plan` uses the values already in `terraform.tfvars`, so you do not
need `-var` flags.

Read the plan output. It creates real, billed GCP resources: a VPC, a
regional GKE cluster, a Cloud SQL instance, a Memorystore Redis instance, a
static IP, and a Cloudflare DNS record. The defaults in `variables.tf` are
the docs' **minimum-spec** tier (`e2-small` nodes, `db-f1-micro`, 1 GB
Redis) to keep the first apply cheap. See "Production sizing" below before
you go live with real users.

When you are ready:

```bash
tofu apply
```

This step takes 15 to 25 minutes. Most of that time is the GKE cluster and
the Cloud SQL instance coming up.

## Step 4: Connect kubectl to the cluster

```bash
gcloud container clusters get-credentials $(tofu output -raw gke_cluster_name) \
  --region us-west1 \
  --project bsp-infisical
```

Check the nodes are ready:

```bash
kubectl get nodes
```

<a id="private-cluster-access"></a>
The cluster has a private control plane. If the command above times out,
run it from Cloud Shell, or add your current IP to the cluster's authorized
networks:

```bash
gcloud container clusters update $(tofu output -raw gke_cluster_name) \
  --region us-west1 \
  --enable-master-authorized-networks \
  --master-authorized-networks $(curl -s ifconfig.me)/32
```

## Step 5: Create the namespace and mirror the secrets

Create the namespace:

```bash
kubectl create namespace infisical
```

OpenTofu already generated `ENCRYPTION_KEY` and `AUTH_SECRET`, and stored
them in Secret Manager along with the database and Redis connection
strings (see `secrets.tf`). Copy them into a native Kubernetes Secret:

```bash
kubectl create secret generic infisical-secrets \
  --from-literal=ENCRYPTION_KEY="$(gcloud secrets versions access latest --secret=infisical-encryption-key)" \
  --from-literal=AUTH_SECRET="$(gcloud secrets versions access latest --secret=infisical-auth-secret)" \
  --from-literal=DB_CONNECTION_URI="$(gcloud secrets versions access latest --secret=infisical-db-uri)" \
  --from-literal=REDIS_URL="$(gcloud secrets versions access latest --secret=infisical-redis-url)" \
  --from-literal=SITE_URL="https://infisical.bigshotpictures.ai" \
  -n infisical
```

Confirm it exists:

```bash
kubectl get secret infisical-secrets -n infisical
```

<Note>
The `google_service_account.gke_workload` Workload Identity binding in
`secrets.tf` grants a GCP service account read access to these same Secret
Manager entries. This step does not use that binding — it copies the
values directly with your own `gcloud` credentials. The binding is there so
you can switch to the Secret Manager CSI driver later without changing
`secrets.tf`. Re-run the `kubectl create secret` command above (or script
it) whenever you rotate a value in Secret Manager, since it does not
auto-sync.
</Note>

## Step 6: Configure SMTP (email)

Without SMTP, sign-up still works, but invites, MFA emails, and login
alerts do not. Big Shot Pictures already uses Google Workspace on
`bigshotpictures.com`, so Workspace SMTP relay is the simplest option if
your Workspace plan allows it. A transactional email provider (for example
Resend or SendGrid) is more reliable at scale and easier to debug.

The `infisical-standalone` Helm chart (Step 7) only reads **one** secret
(`infisical.kubeSecretRef`, set to `infisical-secrets` in
`k8s/infisical-values.yaml`) — there is no second `envFrom` slot for a
separate SMTP secret. Add the SMTP keys into that same secret:

```bash
kubectl patch secret infisical-secrets -n infisical --type=merge -p "$(
  jq -n \
    --arg host "<smtp-host>" \
    --arg port "587" \
    --arg user "<smtp-username>" \
    --arg pass "<smtp-password>" \
    --arg from_addr "infisical@bigshotpictures.com" \
    --arg from_name "Infisical" \
    '{stringData: {
      SMTP_HOST: $host,
      SMTP_PORT: $port,
      SMTP_USERNAME: $user,
      SMTP_PASSWORD: $pass,
      SMTP_FROM_ADDRESS: $from_addr,
      SMTP_FROM_NAME: $from_name
    }}'
)"
```

See the
[Email Service section of the environment variables reference](../../docs/self-hosting/configuration/envars.mdx#email-service)
for the exact host/port/credential values for each provider.

If you skip this step for now, there is nothing else to create — omitting
SMTP keys from `infisical-secrets` is enough; the Helm install below does
not require a placeholder for them.

## Step 7: Install Infisical with Helm

Add the Infisical Helm repository:

```bash
helm repo add infisical-helm-charts https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/
helm repo update
```

Install the **`infisical-standalone`** chart — not the plain `infisical`
chart in the same repo, which pulls in MongoDB by default and is the wrong
one for this Postgres-based deployment:

`k8s/infisical-values.yaml` already has the GSA email
(`infisical-gsa@bsp-infisical.iam.gserviceaccount.com`) and an image tag
(`v0.162.16`) filled in — check Docker Hub for a newer tag before you
deploy if time has passed since this was written.

Note on tag format: versions through `v0.146.0` use a `-postgres` suffix;
`v0.147.0` onward dropped it (Postgres is the only backend now, so a plain
`vX.Y.Z` tag is correct) — see
[`mongo-to-postgres.mdx`](../../docs/self-hosting/guides/mongo-to-postgres.mdx#important-notes).
Do not use `latest`.

Install:

```bash
helm install infisical infisical-helm-charts/infisical-standalone \
  --namespace infisical \
  --values k8s/infisical-values.yaml
```

Watch the pods come up:

```bash
kubectl get pods -n infisical -w
```

Wait until all pods show `Running`.

## Step 8: Apply the managed certificate and HTTPS redirect

```bash
kubectl apply -f k8s/managed-cert.yaml
kubectl apply -f k8s/frontend-config.yaml
```

Check certificate status. Provisioning takes 15 to 60 minutes, and it
cannot start until DNS resolves and the load balancer has an IP:

```bash
kubectl describe managedcertificate infisical-cert -n infisical
```

<Warning>
**If the Ingress never gets an `ADDRESS` and stays stuck for hours, with
zero events and zero GCP load balancer resources ever created** (check
`gcloud compute forwarding-rules list --global`, `--project=<project>`),
this is almost certainly a missing annotation, not a slow provision.

GKE's Ingress controller does not key off `spec.ingressClassName` the way
generic Kubernetes docs would suggest. Per GKE's own docs on
[Ingress for external Application Load Balancers](https://cloud.google.com/kubernetes-engine/docs/concepts/ingress),
if the legacy `kubernetes.io/ingress.class` annotation is unset, the
controller **takes no action at all** — silently, regardless of
`ingressClassName`. `k8s/infisical-values.yaml`'s `ingress.annotations`
already sets `kubernetes.io/ingress.class: "gce"` alongside
`ingressClassName: "gce"` for exactly this reason — both must say `gce`
together. If you ever "clean up" this annotation because it looks
redundant with `ingressClassName`, the Ingress will go silently inert.
</Warning>

If this happens anyway, confirm the annotation actually landed on the live
object (`kubectl get ingress infisical-ingress -n infisical -o yaml`,
under `metadata.annotations`), and confirm the `HttpLoadBalancing` addon
is enabled (`gcloud container clusters describe infisical-cluster
--region us-west1 --format="value(addonsConfig.httpLoadBalancing)"` should
print `{}`, not blank) — `gke.tf` sets this, but it doesn't take effect
retroactively on a running cluster without a `tofu apply`.

## Step 9: Confirm DNS

OpenTofu already created the Cloudflare A record in Step 3, pointed at the
reserved static IP. Confirm it:

```bash
tofu output -raw static_ip_address
dig +short infisical.bigshotpictures.ai
```

The two values must match. If they do not match yet, wait a few minutes for
DNS propagation.

## Step 10: Verify the deployment

```bash
kubectl get ingress -n infisical
curl -I https://infisical.bigshotpictures.ai/api/status
```

A `200` response means the deployment is reachable over HTTPS.

## Step 11: Create the first admin account

The first account created on a fresh instance becomes the instance super
admin. After that account exists, public sign-up turns off automatically —
you invite every other user from inside the app.

Open `https://infisical.bigshotpictures.ai` in a browser and sign up with
your own `@bigshotpictures.com` email address. This is the simplest path
for a small team and needs no extra tooling.

If you instead want a scripted, non-interactive setup (for example to feed
an automation pipeline an admin API token), use the bootstrap API instead
of the UI. Full details, including the response format and the machine
identity it creates, are in
[Programmatic Provisioning](../../docs/self-hosting/guides/automated-bootstrapping.mdx).
Short version:

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"<you>@bigshotpictures.com","password":"<a-strong-password>","organization":"Big Shot Pictures"}' \
  https://infisical.bigshotpictures.ai/api/v1/admin/bootstrap
```

Only run this once. A second call against an already-initialized instance
does not create a second super admin the same way — use the UI invite flow
for every user after the first.

After the first admin exists, open **Admin Console → Authentication** and
confirm **Allow user signups** is set to **Disabled**. This is the default
for a fresh instance, but confirm it — do not skip this check.

## Production sizing

`variables.tf` defaults to the docs' minimum-spec tier so a first `tofu
plan` is cheap. Before real users depend on this instance, raise these
values in `terraform.tfvars` and re-run `tofu apply`:

```hcl
gke_machine_type       = "n2-standard-2"
gke_num_nodes_per_zone = 2
db_tier                = "db-n1-standard-2"
redis_memory_size_gb   = 2
```

Note that `db-n1-standard-2` with `availability_type = "REGIONAL"` (already
set in `database.tf`) runs a synchronous standby replica — this roughly
doubles the Cloud SQL cost shown in the GCP pricing calculator for a single
instance.

## Additional configuration

### Back up the encryption key

`ENCRYPTION_KEY` decrypts every secret Infisical stores. Losing it makes
existing data unrecoverable, even with a full database restore. Store a
copy outside GCP, in a password manager or a physical safe:

```bash
gcloud secrets versions access latest --secret=infisical-encryption-key
```

### Database backups

Cloud SQL automated backups are already on (`backup_configuration` in
`database.tf`). To take a manual backup before a risky change:

```bash
gcloud sql backups create --instance=infisical-db --project=bsp-infisical
```

To restore from one:

```bash
gcloud sql backups restore <backup-id> \
  --restore-instance=infisical-db \
  --backup-instance=infisical-db \
  --project=bsp-infisical
```

### Upgrades

1. Read the release notes for the new version.
2. Take a manual database backup (see above).
3. Update `image.tag` in `k8s/infisical-values.yaml`.
4. Run:
   ```bash
   helm upgrade infisical infisical-helm-charts/infisical-standalone \
     --namespace infisical \
     --values k8s/infisical-values.yaml
   kubectl rollout status deployment/infisical-infisical-standalone-infisical -n infisical
   ```
5. If something breaks, roll back:
   ```bash
   helm rollback infisical -n infisical
   ```

### Debugging

```bash
# Pod status and events
kubectl describe pod <pod-name> -n infisical

# Live logs
kubectl logs -l app=infisical-standalone,release=infisical -n infisical --tail=100 -f

# Shell into a pod
kubectl exec -it <pod-name> -n infisical -- /bin/sh

# Check the pod can reach the database and Redis
kubectl exec -it <pod-name> -n infisical -- nc -zv $(tofu output -raw database_private_ip) 5432
kubectl exec -it <pod-name> -n infisical -- nc -zv $(tofu output -raw redis_host) 6379
```

### Monitoring

Cloud Logging already collects pod logs (`gke.tf` sets
`logging_service`). View them in the GCP Console under **Logging → Logs
Explorer**, filtered to:

```
resource.type="k8s_container" resource.labels.namespace_name="infisical"
```

For application-level metrics, see
[Monitoring and Telemetry Setup](../../docs/self-hosting/guides/monitoring-telemetry.mdx)
and enable `OTEL_TELEMETRY_COLLECTION_ENABLED` in the Helm values' `env`
list.

### Clean up

This deletes real data. Confirm you have backups first.

```bash
helm uninstall infisical -n infisical
kubectl delete namespace infisical
tofu destroy
```

`tofu destroy` removes the VPC, GKE cluster, Cloud SQL instance,
Memorystore instance, static IP, and the Cloudflare DNS record.
`deletion_protection = true` on the Cloud SQL resource (`database.tf`)
blocks accidental destroys of the database — you must remove that line and
re-apply before `tofu destroy` can delete it.
