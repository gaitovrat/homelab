# apps

Argo CD Applications, one file per component. The root app ([`root.yaml`](root.yaml)) syncs every `*.yaml` here, with prune and self-heal: add a file and the component is deployed, delete it and it's removed.

- **Argo CD manages itself** through [`argocd.yaml`](argocd.yaml), and `root` manages itself through `root.yaml`. The Ansible `argocd` role only uses them to bootstrap a new cluster (see [`ansible/README.md`](../ansible/README.md#argo-cd)).
- **One file per component:** chart (`repoURL` + `chart`), exact `targetRevision`, and values inline under `helm.valuesObject`. Renovate opens PRs to bump `targetRevision`; Argo CD syncs after merge.
- **No usable chart:** plain manifests in `manifests/<app>/`, with the Application's `path` pointing there (repo `https://github.com/gaitovrat/homelab.git`, `targetRevision: main`) and `CreateNamespace=true`. Manifests leave out `namespace`; the Application's destination sets it. Renovate bumps image tags there. Used by [`cloudflared.yaml`](cloudflared.yaml), whose chart can't take the token from a SealedSecret.
- **OCI charts:** `repoURL` without `oci://` (e.g. `ghcr.io/argoproj/argo-helm`) and the chart name in `chart`. Public registries need no repository secret.
- **Sync policy:** `automated` with `prune: true` and `selfHeal: true` on every app, so the cluster always matches `main`.
- **No `resources-finalizer`** on an Application unless deleting it should also delete its workloads.
