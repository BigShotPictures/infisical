project_id = "bsp-infisical"
domain     = "infisical.bigshotpictures.ai"
region     = "us-west1"

# e2-small hit GCE_STOCKOUT in us-west1-a and us-west1-c on two separate
# apply attempts (us-west1-b had capacity both times). n2-standard-2 is
# the docs' own "Recommended (Production)" tier anyway, so bumping to it
# now avoids fighting the stockout and skips a second bump-to-production
# step later.
gke_machine_type = "n2-standard-2"

# Skipping Cloudflare for now — no CLOUDFLARE_API_TOKEN needed this way.
# Point infisical.bigshotpictures.ai at the static IP output by hand once
# it's known (see README.md "DNS"), then flip this back to true later if
# you want OpenTofu to own the record.
manage_dns = false

# bigshotpictures.ai zone, looked up via the Cloudflare API. Unused while
# manage_dns is false, but left set so flipping it back on is a one-line
# change.
cloudflare_zone_id = "bb99848f2022831d4ed34ea64331f7fa"
