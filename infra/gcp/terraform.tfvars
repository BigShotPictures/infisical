project_id = "bsp-infisical"
domain     = "infisical.bigshotpictures.ai"
region     = "us-west1"

# e2-small (variables.tf's default) does not have enough allocatable
# memory per node for the infisical-standalone pods — applying it on
# 2026-08-11 left both replicas permanently Pending ("Insufficient
# memory") even after the cluster autoscaler scaled out to its per-zone
# max, causing a real outage. e2-medium has roughly 2x the allocatable
# memory per node and comfortably fits the workload; it still saves
# meaningfully over n2-standard-2.
gke_machine_type = "e2-medium"

# Skipping Cloudflare for now — no CLOUDFLARE_API_TOKEN needed this way.
# Point infisical.bigshotpictures.ai at the static IP output by hand once
# it's known (see README.md "DNS"), then flip this back to true later if
# you want OpenTofu to own the record.
manage_dns = false

# bigshotpictures.ai zone, looked up via the Cloudflare API. Unused while
# manage_dns is false, but left set so flipping it back on is a one-line
# change.
cloudflare_zone_id = "bb99848f2022831d4ed34ea64331f7fa"
