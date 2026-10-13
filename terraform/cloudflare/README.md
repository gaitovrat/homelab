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

## Tunnel token

cloudflared authenticates with the tunnel token. Never commit it or print it in CI; pipe it straight into a Sealed Secret (namespace and name are set by the cloudflared app):

```sh
tofu output -raw tunnel_token \
  | kubectl create secret generic <name> -n <namespace> --from-file=token=/dev/stdin --dry-run=client -o yaml \
  | kubeseal --context homelab -o yaml > <name>.sealed.yaml
```
