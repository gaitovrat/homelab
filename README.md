# homelab

GitOps repository for a single-node Raspberry Pi 4 homelab.

## Stack

- **Hardware:** Raspberry Pi 4 Model B (4 GB, arm64), 256 GB microSD boot, 1 TB USB HDD for data
- **Bootstrap:** Ansible installs the base OS settings, mounts disks, installs k3s and Argo CD
- **Deployments:** Argo CD (app of apps) syncs everything in `apps/` from this repo
- **Charts and images:** own services publish OCI Helm charts and images to `ghcr.io/gaitovrat`
- **Updates:** Renovate opens PRs bumping chart and image versions; Argo CD syncs after merge
- **Ingress:** Cloudflare Tunnel → Traefik, with Cloudflare Access in front of admin apps
- **Cloudflare config:** Terraform in `terraform/cloudflare`, state in Cloudflare R2
- **Secrets:** Sealed Secrets only. This repo is public, so never commit plaintext secrets.

## Layout

```
ansible/              inventory, site.yml, roles (base, disks, k3s, argocd)
apps/                 Argo CD Applications, one per component
terraform/cloudflare/ DNS, tunnel, Access
.github/workflows/    lint and Terraform plan/apply
```

## Status

Work in progress. Directories are added as each part is built.
