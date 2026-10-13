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
