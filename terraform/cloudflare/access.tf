# Cloudflare Access (Zero Trust, free plan) in front of the admin and file apps.
# You sign in with GitHub; friends on the allowlist get a one-time PIN by email,
# and only for FileBrowser. Emails and the GitHub OAuth secret come from
# sensitive variables (1Password locally, Actions secrets in CI), never Git.

# Identity providers

# GitHub OAuth app, created by hand (see README); its callback is
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
resource "cloudflare_zero_trust_access_policy" "friends" {
  count = nonsensitive(length(var.access_friend_emails)) > 0 ? 1 : 0

  account_id       = local.account_id
  name             = "Friends (email PIN)"
  decision         = "allow"
  session_duration = "24h"

  include = [for email in var.access_friend_emails : { email = { email = email } }]
  require = [{ login_method = { id = local.otp_idp_id } }]
}

# Applications

locals {
  access_apps = {
    argocd = {
      name    = "Argo CD"
      friends = false
    }
    files = {
      name    = "FileBrowser"
      friends = true
    }
    # whoami, to test the tunnel and Access end to end.
    test = {
      name    = "Test (whoami)"
      friends = false
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

  # Owner-only apps go straight to GitHub; friends' apps show the choice.
  allowed_idps = concat(
    [cloudflare_zero_trust_access_identity_provider.github.id],
    each.value.friends ? [local.otp_idp_id] : [],
  )
  auto_redirect_to_identity = !each.value.friends

  policies = [
    for i, id in concat(
      [cloudflare_zero_trust_access_policy.owner.id],
      each.value.friends ? cloudflare_zero_trust_access_policy.friends[*].id : [],
    ) : { id = id, precedence = i + 1 }
  ]
}
