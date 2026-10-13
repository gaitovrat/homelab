variable "zone_name" {
  description = "Cloudflare zone (domain) this stack manages. The zone itself comes from Cloudflare Registrar."
  type        = string
  default     = "gaitovrat.dev"
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel that cloudflared in k3s connects with."
  type        = string
  default     = "homelab"
}

variable "tunnel_origin" {
  description = "Where the tunnel sends every *.<zone_name> request: Traefik, which routes by Host."
  type        = string
  default     = "http://traefik.kube-system.svc:80"
}

# Cloudflare Access. Personal data and secrets, so no defaults: locally from
# 1Password (.envrc), in CI from Actions secrets. All sensitive, so plans
# redact them.

variable "access_owner_email" {
  description = "Your email, as GitHub reports it (primary email). Gets every Access app, signing in with GitHub."
  type        = string
  sensitive   = true
}

variable "access_friend_emails" {
  description = "Allowlist for FileBrowser, signing in with a one-time PIN sent by email."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "access_github_client_id" {
  description = "Client ID of the GitHub OAuth app Access signs you in with."
  type        = string
}

variable "access_github_client_secret" {
  description = "Client secret of that GitHub OAuth app."
  type        = string
  sensitive   = true
}
