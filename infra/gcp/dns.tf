# A record, not CNAME: this points directly at a reserved GCP static IP
# (google_compute_global_address.ingress in gke.tf), not a Vercel-style
# hostname target.
#
# proxied = false is required, not optional, here: the GKE Ingress's
# Google-managed certificate (see the docs' "Configure HTTPS access with
# SSL/TLS" step) validates and terminates TLS directly against this IP.
# Cloudflare proxying would put Cloudflare's edge IP in front instead,
# breaking certificate issuance/renewal.
resource "cloudflare_dns_record" "infisical" {
  count = var.manage_dns ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "A"
  content = google_compute_global_address.ingress.address
  ttl     = 1
  proxied = false
}
