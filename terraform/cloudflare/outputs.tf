output "tunnel_id" {
  description = "ID of the Cloudflare Tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "tunnel_token" {
  description = "Token cloudflared runs the tunnel with. Seal it, never commit it: tofu output -raw tunnel_token."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab.token
  sensitive   = true
}

output "argocd_oidc_issuer" {
  description = "OIDC issuer URL for Argo CD's oidc.config."
  value       = "https://${data.cloudflare_zero_trust_organization.this.auth_domain}/cdn-cgi/access/sso/oidc/${cloudflare_zero_trust_access_application.argocd_oidc.saas_app.client_id}"
}

output "argocd_oidc_client_id" {
  description = "OIDC client ID for Argo CD's oidc.config."
  value       = cloudflare_zero_trust_access_application.argocd_oidc.saas_app.client_id
}

output "argocd_oidc_client_secret" {
  description = "OIDC client secret for Argo CD. Seal it, never commit it (see README)."
  value       = cloudflare_zero_trust_access_application.argocd_oidc.saas_app.client_secret
  sensitive   = true
}
