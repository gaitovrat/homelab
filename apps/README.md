# apps

Argo CD Applications, one file per component. The root app ([`root.yaml`](root.yaml)) syncs every `*.yaml` here, with prune and self-heal: add a file and the component is deployed, delete it and it's removed.

- **Argo CD manages itself** through [`argocd.yaml`](argocd.yaml), and `root` manages itself through `root.yaml`. The Ansible `argocd` role only uses them to bootstrap a new cluster (see [`ansible/README.md`](../ansible/README.md#argo-cd)).
- **One file per component:** chart (`repoURL` + `chart`), exact `targetRevision`, and values inline under `helm.valuesObject`. Renovate opens PRs to bump `targetRevision`; Argo CD syncs after merge.
- **No usable chart:** plain manifests in `manifests/<app>/`, with the Application's `path` pointing there (repo `https://github.com/gaitovrat/homelab.git`, `targetRevision: main`) and `CreateNamespace=true`. Manifests leave out `namespace`; the Application's destination sets it. Renovate bumps image tags there. Used by [`cloudflared.yaml`](cloudflared.yaml), whose chart can't take the token from a SealedSecret.
- **OCI charts:** `repoURL` without `oci://` (e.g. `ghcr.io/argoproj/argo-helm`) and the chart name in `chart`. Public registries need no repository secret.
- **Sync policy:** `automated` with `prune: true` and `selfHeal: true` on every app, so the cluster always matches `main`.
- **No `resources-finalizer`** on an Application unless deleting it should also delete its workloads.

## Reaching Argo CD

- **UI:** https://argocd.gaitovrat.dev, behind Cloudflare Access (you only, GitHub login; see [`terraform/cloudflare`](../terraform/cloudflare/README.md#access)). Then **Log in via Cloudflare Access**: Access is also Argo CD's OIDC provider, so it reuses the same session. RBAC gives `role:admin` to your Access user ID (the token's `sub`) and nothing to anyone else. The client secret is the SealedSecret in [`manifests/argocd-oidc`](../manifests/argocd-oidc), synced by [`argocd-oidc.yaml`](argocd-oidc.yaml). TLS ends at Cloudflare, so the server runs with `server.insecure` and Traefik routes plain HTTP to it.
- **CLI:** `argocd` from the dev shell, in core mode: it talks to the Kubernetes API over Tailscale with the repo's kubeconfig, so it skips Access and needs no Argo CD login. Point the context at the `argocd` namespace once (`kubens argocd`), then e.g. `argocd app list --core`, `argocd app sync <app> --core`, or `argocd admin dashboard` for the UI on localhost.

## FileBrowser

[`filebrowser.yaml`](filebrowser.yaml) → [`manifests/filebrowser`](../manifests/filebrowser): FileBrowser Quantum at https://files.gaitovrat.dev, serving the USB HDD (`/mnt/disks/hdd1`, exFAT, uid 1000) with its database, index and thumbnails on a `local-path` volume.

- **Login:** Cloudflare Access only (you with GitHub, allowed emails with a PIN). FileBrowser takes the `Cf-Access-Authenticated-User-Email` header as the username and creates users on first visit; there are no passwords. Your email is `adminUsername`, so your account is admin on every login. It's a SealedSecret (`filebrowser-owner`) filled into the config at pod start; to change it, reseal: `printf %s <email> | kubectl create secret generic filebrowser-owner -n filebrowser --from-file=email=/dev/stdin --dry-run=client -o yaml | kubeseal --context homelab -o yaml > manifests/filebrowser/filebrowser-owner.sealed.yaml`.
- **Everyone who can sign in gets the whole disk** (view, download, upload, modify, delete, share); only you get admin settings.
- **Security:** FileBrowser trusts that header blindly. Through the tunnel, Cloudflare Access sets it; but anyone on the home LAN can reach Traefik directly with `Host: files.gaitovrat.dev` and a forged header, and become admin.
- **Disk missing:** the pod won't start unless `/srv/hdd1` is the exFAT HDD, so uploads never land on the SD card under an empty mount point.
