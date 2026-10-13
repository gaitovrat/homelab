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

## Tunnel token

cloudflared authenticates with the tunnel token. Never commit it or print it in CI; pipe it straight into the SealedSecret cloudflared reads ([`manifests/cloudflared`](../../manifests/cloudflared)). Reseal only if the tunnel is recreated:

```sh
tofu output -raw tunnel_token \
  | kubectl create secret generic cloudflared-token -n cloudflared --from-file=token=/dev/stdin --dry-run=client -o yaml \
  | kubeseal --context homelab -o yaml > ../../manifests/cloudflared/cloudflared-token.sealed.yaml
```
