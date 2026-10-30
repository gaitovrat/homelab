# Cloudflare Access (Zero Trust, free plan) in front of the admin and file apps.
# You sign in with GitHub; people on the allowlist get a one-time PIN by email,
# and only for FileBrowser. Emails and the GitHub OAuth App secret come from
# sensitive variables (1Password locally, Actions secrets in CI), never Git.

# Identity providers

# GitHub OAuth App, created by hand (see README); its callback is
# https://<team>.cloudflareaccess.com/cdn-cgi/access/callback.
resource "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = local.account_id
  name       = "GitHub"
  type       = "github"
  config = {
    client_id     = var.access_github_client_id
    client_secret = var.access_github_client_secret
  }
}

# The one-time PIN provider comes with every Zero Trust account and has no
# settings, so it's looked up rather than managed.
data "cloudflare_zero_trust_access_identity_providers" "all" {
  account_id = local.account_id
}

locals {
  otp_idp_id = one([
    for idp in data.cloudflare_zero_trust_access_identity_providers.all.result : idp.id
    if idp.type == "onetimepin"
  ])
}

# Policies

resource "cloudflare_zero_trust_access_policy" "owner" {
  account_id       = local.account_id
  name             = "Owner (GitHub)"
  decision         = "allow"
  session_duration = "24h"

  include = [{ email = { email = var.access_owner_email } }]
  require = [{ login_method = { id = cloudflare_zero_trust_access_identity_provider.github.id } }]
}

# Skipped while the allowlist is empty: a policy needs at least one include rule.
resource "cloudflare_zero_trust_access_policy" "allowed" {
  count = nonsensitive(length(var.access_allowed_emails)) > 0 ? 1 : 0

  account_id       = local.account_id
  name             = "Allowed emails (email PIN)"
  decision         = "allow"
  session_duration = "24h"

  include = [for email in var.access_allowed_emails : { email = { email = email } }]
  require = [{ login_method = { id = local.otp_idp_id } }]
}

# Applications

locals {
  access_apps = {
    argocd = {
      name           = "Argo CD"
      allowed_emails = false
    }
    files = {
      name           = "FileBrowser"
      allowed_emails = true
    }
    stats = {
      name           = "Grafana"
      allowed_emails = false
    }
    # whoami, to test the tunnel and Access end to end.
    test = {
      name           = "Test (whoami)"
      allowed_emails = false
    }
  }
}

resource "cloudflare_zero_trust_access_application" "this" {
  for_each = local.access_apps

  account_id       = local.account_id
  name             = each.value.name
  domain           = "${each.key}.${var.zone_name}"
  type             = "self_hosted"
  session_duration = "24h"

  # Owner-only apps go straight to GitHub; apps open to the allowlist show the choice.
  allowed_idps = concat(
    [cloudflare_zero_trust_access_identity_provider.github.id],
    each.value.allowed_emails ? [local.otp_idp_id] : [],
  )
  auto_redirect_to_identity = !each.value.allowed_emails

  policies = [
    for i, id in concat(
      [cloudflare_zero_trust_access_policy.owner.id],
      each.value.allowed_emails ? cloudflare_zero_trust_access_policy.allowed[*].id : [],
    ) : { id = id, precedence = i + 1 }
  ]
}

data "cloudflare_zero_trust_organization" "this" {
  account_id = local.account_id
}

# Argo CD SSO: Access acts as an OIDC provider for Argo CD (no Dex). Only the
# owner policy is attached, so only you can get a token; Argo CD maps your
# Access user ID to admin (apps/argocd.yaml). The client secret is sealed into
# manifests/argocd-oidc (see README).
resource "cloudflare_zero_trust_access_application" "argocd_oidc" {
  account_id       = local.account_id
  name             = "Argo CD SSO"
  type             = "saas"
  session_duration = "24h"

  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.github.id]
  auto_redirect_to_identity = true
  app_launcher_visible      = false

  saas_app = {
    auth_type     = "oidc"
    redirect_uris = ["https://argocd.${var.zone_name}/auth/callback"]
    grant_types   = ["authorization_code"]
    scopes        = ["openid", "email", "profile"]
  }

  policies = [{ id = cloudflare_zero_trust_access_policy.owner.id, precedence = 1 }]
}
