data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

locals {
  zone_id    = data.cloudflare_zone.this.zone_id
  account_id = data.cloudflare_zone.this.account.id
}

# Zone settings

locals {
  zone_settings = {
    # TLS at the edge. Traffic to the origin goes through the tunnel, which is encrypted
    # on its own, so the mode only matters if a proxied record ever points elsewhere.
    ssl                      = "full"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"
    always_use_https         = "on"
    automatic_https_rewrites = "on"
  }
}

resource "cloudflare_zone_setting" "this" {
  for_each = local.zone_settings

  zone_id    = local.zone_id
  setting_id = each.key
  value      = each.value
}

# Tunnel

# Remotely managed: the ingress rules live in Cloudflare (below), and cloudflared only
# needs the token.
resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = local.account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config = {
    ingress = [
      # The apex (landing page) goes to Traefik too; the wildcard doesn't match it.
      {
        hostname = var.zone_name
        service  = var.tunnel_origin
      },
      # Every subdomain goes to Traefik, so adding an app needs only an Ingress.
      {
        hostname = "*.${var.zone_name}"
        service  = var.tunnel_origin
      },
      # cloudflared requires a catch-all rule last.
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "homelab" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

# DNS

resource "cloudflare_dns_record" "wildcard" {
  zone_id = local.zone_id
  name    = "*.${var.zone_name}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # automatic; required for proxied records
  comment = "Cloudflare Tunnel ${var.tunnel_name} (managed by Terraform)"
}

# The wildcard doesn't cover the apex. Cloudflare flattens a CNAME there.
resource "cloudflare_dns_record" "apex" {
  zone_id = local.zone_id
  name    = var.zone_name
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # automatic; required for proxied records
  comment = "Cloudflare Tunnel ${var.tunnel_name} (managed by Terraform)"
}
