# homelab

Planning context, decisions and tasks live in the private sibling repo `homelab-tasks`.
Clone it next to this repo (`../homelab-tasks`) so the import below resolves:

@../homelab-tasks/CLAUDE.md

If the import is missing, read `README.md` here and ask before making architectural choices.

## Rules for this repo
- Public repo: never commit plaintext secrets, tokens, kubeconfigs or private IPs. Use Sealed Secrets.
- Never push to `main`; branch and open a PR referencing `gaitovrat/homelab-tasks#N`.
