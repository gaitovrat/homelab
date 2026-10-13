# homelab

GitOps repository for a single-node Raspberry Pi 4 homelab.

## Stack

- **Hardware:** Raspberry Pi 4 Model B (4 GB, arm64), 256 GB microSD boot, 1 TB USB HDD for data
- **Bootstrap:** Ansible installs the base OS settings, mounts disks, installs k3s and bootstraps Argo CD
- **Deployments:** Argo CD (app of apps) syncs everything in `apps/` from this repo, Argo CD itself included
- **Charts and images:** own services publish OCI Helm charts and images to `ghcr.io/gaitovrat`
- **Updates:** Renovate opens PRs bumping chart and image versions; Argo CD syncs after merge
- **Ingress:** Cloudflare Tunnel → Traefik, with Cloudflare Access in front of admin apps
- **Cloudflare config:** Terraform in `terraform/cloudflare`, state in Cloudflare R2
- **Secrets:** Sealed Secrets only (see [Secrets](#secrets)). This repo is public, so never commit plaintext secrets.

## Layout

```
ansible/              inventory, site.yml, roles (base, disks, k3s, argocd)
apps/                 Argo CD Applications, one per component
terraform/cloudflare/ DNS, tunnel, Access
.github/workflows/    lint and Terraform plan/apply
```

## Tools

Every CLI this repo needs (Ansible and ansible-lint, kubectl, helm, kubeseal, jq, gh, actionlint, shellcheck) comes from the Nix dev shell in [`flake.nix`](flake.nix), pinned by `flake.lock`, the same on macOS, Linux and WSL. Ansible and ansible-lint are installed into `.venv` from [`.github/requirements-lint.txt`](.github/requirements-lint.txt), so local runs use the versions CI lints with. Renovate bumps both files.

One-time setup per machine:

1. Install Nix with flakes on: `curl -fsSL https://install.determinate.systems/nix | sh -s -- install` (on WSL, enable systemd first: `[boot] systemd=true` in `/etc/wsl.conf`, then `wsl --shutdown`).
2. Install Tailscale and log in to the tailnet. `site.yml`, `ssh` and kubectl reach the nodes only by their MagicDNS names. Tailscale runs as a system daemon (`tailscaled`), so it can't come from the dev shell, which warns when it's missing:
   - macOS: the [Tailscale app](https://tailscale.com/download/mac), with its CLI on `PATH` (app settings → CLI integration) so the dev shell can check it.
   - Linux and WSL: `curl -fsSL https://tailscale.com/install.sh | sh`, then `sudo tailscale up`. On WSL this installs Tailscale inside the distro and needs systemd (see step 1). WSL then shows up as a machine of its own in the admin console.
3. Install the 1Password app and its CLI (`op`), and turn on app → Settings → Developer → **Integrate with 1Password CLI**. The CLI has to be installed next to the app to unlock through it, so it can't come from the dev shell. The Ansible vault key and the Sealed Secrets key backup live there; see [`ansible/README.md`](ansible/README.md#one-time-setup).
4. Optional, to enter the shell on `cd`: install [direnv](https://direnv.net) and [nix-direnv](https://github.com/nix-community/nix-direnv), then `direnv allow` in the repo.

Then `nix develop` (or just `cd` with direnv) gives a shell with everything on `PATH`. The first run downloads the tools and builds `.venv`; later runs are instant. To add a tool, add it to `packages` in `flake.nix`.

## Secrets

This repo is public, so every Kubernetes secret is committed as a **SealedSecret**: encrypted with the cluster's public key, decrypted in the cluster by the Sealed Secrets controller ([`apps/sealed-secrets.yaml`](apps/sealed-secrets.yaml), in `kube-system`). Only that controller holds the private key. Ansible secrets are separate, see [`ansible/README.md`](ansible/README.md#secrets-ansible-vault--1password).

The controller has a single sealing key and never rotates it (`keyrenewperiod: "0"`), so one backup restores every SealedSecret.

### Sealing a secret

`kubeseal` comes with the [dev shell](#tools). Build the Secret locally with `--dry-run` (nothing reaches the cluster) and seal it:

```sh
kubectl create secret generic <name> -n <namespace> \
  --from-file=<key>=<path-to-value> --dry-run=client -o yaml \
  | kubeseal --context homelab -o yaml > <name>.sealed.yaml
```

- Commit only the `*.sealed.yaml` output, never the input. Prefer `--from-file` over `--from-literal` so values don't land in shell history.
- A SealedSecret only decrypts under the name and namespace it was sealed for; to change either, seal again.
- To change one value, seal again, or merge into the existing file: `... | kubeseal --context homelab -o yaml --merge-into <name>.sealed.yaml`.

### Backing up the sealing key

The private key is a Secret in `kube-system` labelled `sealedsecrets.bitnami.com/sealed-secrets-key`. Without it, a rebuilt cluster can't decrypt anything in this repo, so it's kept in 1Password next to the Ansible vault key. Once, after the controller first starts:

```sh
kubectl --context homelab -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o json \
  | jq '{apiVersion: "v1", kind: "List", items: [.items[] | {apiVersion, kind, type, data,
         metadata: {name: .metadata.name, namespace: .metadata.namespace, labels: .metadata.labels}}]}' \
  | op document create - --vault Homelab --title homelab-sealed-secrets-key --file-name sealed-secrets-key.json
```

`jq` keeps only what a restore needs (no `uid` or `resourceVersion`, which a new cluster would reject). The key never touches the disk. If the controller ever gets a new key (a key secret was deleted, or `keyrenewperiod` changed), replace the backup: same pipeline, ending in `op document edit homelab-sealed-secrets-key - --vault Homelab`.

### Restoring the key

On a rebuilt cluster, Argo CD deploys the controller, which generates a fresh key on its first start. Swap that key for the backup and restart the controller:

```sh
kubectl --context homelab -n kube-system delete secret -l sealedsecrets.bitnami.com/sealed-secrets-key
op document get homelab-sealed-secrets-key --vault Homelab | kubectl --context homelab apply -f -
kubectl --context homelab -n kube-system rollout restart deployment sealed-secrets-controller
```

Check: `kubectl --context homelab get sealedsecrets -A` shows every SealedSecret as synced, and the cert from `kubeseal --context homelab --fetch-cert` is the same as before.

## Status

Work in progress. Directories are added as each part is built.
