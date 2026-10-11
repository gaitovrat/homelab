# Ansible

Bootstraps the k3s nodes. Run everything from this directory so `ansible.cfg` is picked up.

```sh
cd ansible
ansible-playbook site.yml          # Touch ID once, for the vault key
ansible-playbook site.yml --check  # dry run
```

Per-node settings go in `inventory/host_vars/<host>/`: plain values in any `.yml` there, and secrets in its encrypted `vault.yml` (see below).

## Secrets: Ansible Vault + 1Password

Secrets live **in the repo, encrypted** with Ansible Vault (AES-256). Nothing secret is passed on the command line or through env vars.

| File | Holds |
|---|---|
| `inventory/group_vars/all/vault.yml` | secrets shared by all nodes: `tailscale_authkey` |
| `inventory/host_vars/<host>/vault.yml` | per-node secrets: `ansible_become_password` (sudo password) |

Ansible loads both automatically; for the same variable, the host's value wins. All files use the same key (the *vault password*), which is in 1Password, never in the repo.

`ansible.cfg` sets `vault_password_file = vault-pass.sh`. Ansible runs that script, it prints the key via `op read`, and the vault decrypts with no prompt. The 1Password reference defaults to `op://Homelab/homelab-ansible-vault/password`; set `ANSIBLE_VAULT_OP_REF` to use another.

### One-time setup

1. Install the CLI (`brew install 1password-cli`) and turn on 1Password → Settings → Developer → **Integrate with 1Password CLI**, so `op` unlocks through the app with Touch ID.
2. Generate the vault key in 1Password:

   ```sh
   op item create --category=password --vault=Homelab --title=homelab-ansible-vault \
     --generate-password='letters,digits,symbols,48'
   ./vault-pass.sh >/dev/null && echo ok   # the script can read it
   ```

3. For each node, create its encrypted file (opens `$EDITOR`; write `ansible_become_password: <that node's sudo password>`, save, quit):

   ```sh
   mkdir -p inventory/host_vars/k3s-01
   ansible-vault create inventory/host_vars/k3s-01/vault.yml
   ```

   Commit it: it's encrypted (`$ANSIBLE_VAULT;1.1;AES256` header), so it's safe in this public repo.

### Day to day

```sh
ansible-vault view inventory/host_vars/k3s-01/vault.yml    # read
ansible-vault edit inventory/host_vars/k3s-01/vault.yml    # change (re-encrypts on save)
ansible-vault rekey inventory/group_vars/all/vault.yml inventory/host_vars/*/vault.yml   # after rotating the key in 1Password
```

Keep the key safe: anyone with it and repo access can decrypt every secret here. Losing it means re-creating the vault files. No 1Password at hand? `ansible-playbook site.yml --ask-vault-pass` prompts for the key instead.

## How nodes are addressed

By name only, never by IP, and only over Tailscale. `group_vars/all/main.yml` sets `tailnet_domain` and makes `ansible_host` the node's MagicDNS name, `<inventory_hostname>.<tailnet_domain>` (e.g. `k3s-01.tailbc9346.ts.net`). It works from anywhere the laptop is on the tailnet.

The one exception is a node's first run, before it's on the tailnet: point that run at mDNS on the LAN with `-e ansible_host=<host>.local --limit <host>` (see [Tailscale first run](#first-run-node-not-on-the-tailnet-yet)).

Per-node overrides (e.g. `ansible_user`, if your SSH user differs from your local username) go in `host_vars/<host>/`.

## Roles

| Role | Does |
|---|---|
| `base` | Base packages; `cgroup_memory=1 cgroup_enable=memory` in `cmdline.txt` (k3s needs the memory cgroup); zram-only swap via rpi-swap (no swap file on the SD card); journald in RAM only, capped at 64M; unattended security upgrades (no auto-reboot). Reboots the node when the cmdline or swap config changes. |
| `tailscale` | Official apt repo, pinned `tailscale` (Renovate bumps it), `tailscaled` enabled; `tailscale up` with the node's inventory name, skipped once the node is up. |

## Tailscale

### First run (node not on the tailnet yet)

1. In the [admin console → Settings → Keys](https://login.tailscale.com/admin/settings/keys), generate an auth key: **reusable** (one key onboards every node), **not ephemeral**, expiry up to 90 days, pre-approved if device approval is on, no tags.
2. Put it in the shared vault (creates the file the first time; `edit` afterwards), then commit the encrypted file:

   ```sh
   ansible-vault create inventory/group_vars/all/vault.yml   # tailscale_authkey: tskey-auth-...
   ```

3. Add the node to `inventory/hosts.yml`, then run it once over the LAN via mDNS (it has no MagicDNS name yet):

   ```sh
   ansible-playbook site.yml --limit k3s-02 -e ansible_host=k3s-02.local
   ```

   The key is never logged (`no_log`) and only used for a node's first login: later runs see the node is up and skip `tailscale up`. When the key expires, nodes already on the tailnet are unaffected; generate a new one and `ansible-vault edit` it in before onboarding the next node. You can also revoke it in the console once all nodes have joined.
4. In the [Machines](https://login.tailscale.com/admin/machines) page, open the node → **Disable key expiry**. Otherwise the node drops off the tailnet when its key expires (180 days by default).
5. Check the node's name on the Machines page is exactly its inventory name (not `k3s-02-1`). From now on plain `ansible-playbook site.yml`, `ssh` and kubectl reach it over the tailnet.

The node runs with `--accept-dns=false`: it never needs to resolve tailnet names, and this keeps its DNS (and so k3s CoreDNS) independent of `tailscaled`.

## Check

```sh
ansible-playbook site.yml                      # second run: changed=0
ssh k3s-01.tailbc9346.ts.net 'cat /sys/fs/cgroup/cgroup.controllers; cat /proc/swaps; ls /var/swap'
# expect "memory" in the controllers, only /dev/zram0 as swap, and no /var/swap

tailscale status                               # k3s-01 listed, online
```
