# terraform/cloudflare

Cloudflare config for `gaitovrat.dev`, as plain Terraform run with OpenTofu (from the [dev shell](../../README.md#tools)):

- **Zone settings:** SSL Full, TLS 1.2 minimum, TLS 1.3, Always Use HTTPS, Automatic HTTPS Rewrites. The zone itself comes from Cloudflare Registrar and is only read here.
- **Tunnel `homelab`:** remotely managed, so the ingress rules live in Cloudflare and cloudflared in k3s only needs a token. One rule: `*.gaitovrat.dev` → `http://traefik.kube-system.svc:80`; Traefik routes by Host, so a new app needs only an Ingress, not a change here. Anything else gets a 404.
- **DNS:** a proxied wildcard CNAME `*.gaitovrat.dev` → `<tunnel-id>.cfargotunnel.com`.
- **Output `tunnel_token`** (sensitive), for the cloudflared Sealed Secret.

State is in the R2 bucket `homelab-tfstate` (key `cloudflare/terraform.tfstate`), through the S3 backend, with a lock file next to it.

## One-time setup (by hand)

Terraform can't create the bucket it keeps its own state in, or the token it runs with, so these are made once in the Cloudflare dashboard and kept in 1Password (vault `Homelab`):

1. **R2 bucket:** R2 → Create bucket → `homelab-tfstate`, location automatic.
2. **R2 access key:** R2 → Manage API tokens → Create API token, permission **Object Read & Write**, limited to `homelab-tfstate`. Save it as a 1Password login `homelab-tfstate-r2`: *username* = Access Key ID, *password* = Secret Access Key.
3. **API token:** My Profile → API Tokens → Create Custom Token, named `homelab-terraform`:
   - Zone → Zone → Read, Zone → Zone Settings → Edit, Zone → DNS → Edit; zone resources: `gaitovrat.dev` only.
   - Account → Cloudflare Tunnel → Edit; account resources: your account.
   - Later, for Cloudflare Access (gaitovrat/homelab-tasks#14): Account → Access: Apps and Policies → Edit.

   Save it as a 1Password API Credential `homelab-cloudflare-terraform`: the token in *credential*, plus a text field `account_id` with the account ID (dashboard → account home → Account ID).

## Running

[`tofu.sh`](tofu.sh) reads four values from 1Password in one `op inject` (on WSL through the Windows `op.exe`) into the same variables as the repo's GitHub Actions secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. It derives the R2 endpoint `AWS_ENDPOINT_URL_S3` from the account ID and runs `tofu` in this directory. Nothing is written to disk or shell history.

```sh
cd terraform/cloudflare
./tofu.sh init
./tofu.sh plan
./tofu.sh apply
```

Another vault: `HOMELAB_OP_VAULT=<vault> ./tofu.sh plan`. Without 1Password, set those four variables plus `AWS_ENDPOINT_URL_S3=https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com` yourself and run `tofu` directly.

From gaitovrat/homelab-tasks#12 on, `plan` runs on PRs and `apply` on merge to `main` in GitHub Actions; run it by hand only for the first apply or to debug.

## Tunnel token

cloudflared authenticates with the tunnel token. Never commit it or print it in CI; pipe it straight into a Sealed Secret (namespace and name are set by the cloudflared app, gaitovrat/homelab-tasks#13):

```sh
./tofu.sh output -raw tunnel_token \
  | kubectl create secret generic <name> -n <namespace> --from-file=token=/dev/stdin --dry-run=client -o yaml \
  | kubeseal --context homelab -o yaml > <name>.sealed.yaml
```

## Versions

The Cloudflare provider is pinned in [`versions.tf`](versions.tf) and [`.terraform.lock.hcl`](.terraform.lock.hcl) (hashes for linux_amd64, linux_arm64 and darwin_arm64); Renovate bumps both. After changing providers by hand, refresh the lock for every platform:

```sh
tofu providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64
```
