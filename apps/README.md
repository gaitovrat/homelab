# apps

Argo CD Applications, one file per component. The root app (`root` in the `argocd` namespace, applied by the Ansible `argocd` role) syncs every `*.yaml` here, with prune and self-heal: add a file and the component is deployed, delete it and it's removed.

Pin each chart's `targetRevision` to an exact version; Renovate opens PRs to bump it.
