# terraform/cloudflare

Cloudflare config for `gaitovrat.dev`, as plain Terraform run with OpenTofu (from the [dev shell](../../README.md#tools)):
State is in the R2 bucket `homelab-tfstate` (key `cloudflare/terraform.tfstate`), through the S3 backend, with a lock file next to it.

## Running

With direnv, `.envrc` here loads the Cloudflare and R2 credentials from 1Password (same names as the repo's Actions secrets) when you `cd` in, and drops them when you leave.

```sh
cd terraform/cloudflare
tofu init
tofu plan
tofu apply
```

## CI

[`.github/workflows/terraform.yml`](../../.github/workflows/terraform.yml) runs on changes under `terraform/`:

- **PR:** `fmt`, `validate` and `plan`. The PR gets one comment, updated on each push, listing which resources change and how, with no values: the repo is public, and comments aren't masked like the run log. The full plan is in the run log.
- **Merge to `main`:** `plan` and `apply` in the `cloudflare` environment, which waits for your approval and only deploys from `main`.

Credentials are the repo's Actions secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Run by hand only to debug, or when CI is broken.

## Access

Cloudflare Access ([`access.tf`](access.tf)) puts a login in front of `argocd`, `files` and `test`:

| App | Who |
|---|---|
| `argocd.gaitovrat.dev`, `test.gaitovrat.dev` | you, signing in with GitHub (sent straight to GitHub) |
| `files.gaitovrat.dev` | you with GitHub, and the allowed emails with a one-time PIN by email |

The emails and the GitHub OAuth app are sensitive variables, kept out of this public repo. One-time setup:

1. **GitHub OAuth app:** GitHub → Settings → Developer settings → OAuth Apps → New, homepage `https://gaitovrat.cloudflareaccess.com`, callback `https://gaitovrat.cloudflareaccess.com/cdn-cgi/access/callback`. Generate a client secret.
2. **1Password:** item `Cloudflare Access` in `Homelab` with text fields `owner email` (your GitHub primary email), `allowed emails` (JSON list, e.g. `["a@example.com"]`, or `[]`), `github client id`, and a password field `github client secret`. `.envrc` loads them as `TF_VAR_access_*`.
3. **Actions secrets:** `ACCESS_OWNER_EMAIL`, `ACCESS_ALLOWED_EMAILS`, `ACCESS_GITHUB_CLIENT_ID`, `ACCESS_GITHUB_CLIENT_SECRET`, with the same values.
4. **API token:** add Account → Access: Apps and Policies → Edit, and Account → Access: Organizations, Identity Providers, and Groups → Edit.

To change the allowlist, edit `allowed emails` in 1Password and `ACCESS_ALLOWED_EMAILS`, then apply (by hand, or re-run the `terraform` workflow on `main`).

## Tunnel token

cloudflared authenticates with the tunnel token. Never commit it or print it in CI; pipe it straight into the SealedSecret cloudflared reads ([`manifests/cloudflared`](../../manifests/cloudflared)). Reseal only if the tunnel is recreated:

```sh
tofu output -raw tunnel_token \
  | kubectl create secret generic cloudflared-token -n cloudflared --from-file=token=/dev/stdin --dry-run=client -o yaml \
  | kubeseal --context homelab -o yaml > ../../manifests/cloudflared/cloudflared-token.sealed.yaml
```
