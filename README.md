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

## Secrets

This repo is public, so every Kubernetes secret is committed as a **SealedSecret**: encrypted with the cluster's public key, decrypted in the cluster by the Sealed Secrets controller ([`apps/sealed-secrets.yaml`](apps/sealed-secrets.yaml), in `kube-system`). Only that controller holds the private key. Ansible secrets are separate, see [`ansible/README.md`](ansible/README.md#secrets-ansible-vault--1password).

The controller has a single sealing key and never rotates it (`keyrenewperiod: "0"`), so one backup restores every SealedSecret.

### Sealing a secret

Install the client once: `brew install kubeseal`. Then build the Secret locally with `--dry-run` (nothing reaches the cluster) and seal it:

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
