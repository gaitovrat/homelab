output "tunnel_id" {
  description = "ID of the Cloudflare Tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "tunnel_token" {
  description = "Token cloudflared runs the tunnel with. Seal it, never commit it: tofu output -raw tunnel_token."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab.token
  sensitive   = true
}
