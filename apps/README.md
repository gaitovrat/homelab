# apps

Argo CD Applications, one file per component. The root app ([`root.yaml`](root.yaml)) syncs every `*.yaml` here, with prune and self-heal: add a file and the component is deployed, delete it and it's removed.

- **Argo CD manages itself** through [`argocd.yaml`](argocd.yaml), and `root` manages itself through `root.yaml`. The Ansible `argocd` role only uses them to bootstrap a new cluster (see [`ansible/README.md`](../ansible/README.md#argo-cd)).
- **One file per component:** chart (`repoURL` + `chart`), exact `targetRevision`, and values inline under `helm.valuesObject`. Renovate opens PRs to bump `targetRevision`; Argo CD syncs after merge.
- **No usable chart:** plain manifests in `manifests/<app>/`, with the Application's `path` pointing there (repo `https://github.com/gaitovrat/homelab.git`, `targetRevision: main`) and `CreateNamespace=true`. Manifests leave out `namespace`; the Application's destination sets it. Renovate bumps image tags there. Used by [`cloudflared.yaml`](cloudflared.yaml), whose chart can't take the token from a SealedSecret.
- **OCI charts:** `repoURL` without `oci://` (e.g. `ghcr.io/argoproj/argo-helm`) and the chart name in `chart`. Public registries need no repository secret.
- **Sync policy:** `automated` with `prune: true` and `selfHeal: true` on every app, so the cluster always matches `main`.
- **No `resources-finalizer`** on an Application unless deleting it should also delete its workloads.

## Reaching Argo CD

- **UI:** https://argocd.gaitovrat.dev, behind Cloudflare Access (you only, GitHub login; see [`terraform/cloudflare`](../terraform/cloudflare/README.md#access)), then Argo CD's own `admin` login. The initial password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`. TLS ends at Cloudflare, so the server runs with `server.insecure` and Traefik routes plain HTTP to it.
- **CLI:** `argocd` from the dev shell, in core mode: it talks to the Kubernetes API over Tailscale with the repo's kubeconfig, so it skips Access and needs no Argo CD login. Point the context at the `argocd` namespace once (`kubens argocd`), then e.g. `argocd app list --core`, `argocd app sync <app> --core`, or `argocd admin dashboard` for the UI on localhost.
