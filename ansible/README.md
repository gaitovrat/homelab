# Ansible

Bootstraps the k3s nodes. Run everything from this directory so `ansible.cfg` is picked up.

```sh
cd ansible
ansible-playbook site.yml          # Touch ID once, for the vault key
ansible-playbook site.yml --check  # dry run
```

Optional per-machine settings (SSH user, domain) go in `inventory/group_vars/all/local.yml`, which is gitignored; see `local.yml.example`.

## Secrets: Ansible Vault + 1Password

Secrets live **in the repo, encrypted** with Ansible Vault (AES-256), one file per node: `inventory/host_vars/<host>/vault.yml`. Right now that's only `ansible_become_password`, the node's sudo password, which differs per node. Ansible loads `host_vars/<inventory_hostname>/` automatically. A `group_vars/all/vault.yml` can hold a shared fallback; host values win. All files use the same key (the *vault password*), which is in 1Password, never in the repo.

`ansible.cfg` sets `vault_password_file = vault-pass.sh`. Ansible runs that script, it prints the key via `op read`, and the vault decrypts with no prompt. The 1Password reference defaults to `op://Private/homelab-ansible-vault/password`; set `ANSIBLE_VAULT_OP_REF` to use another.

### One-time setup

1. Install the CLI (`brew install 1password-cli`) and turn on 1Password → Settings → Developer → **Integrate with 1Password CLI**, so `op` unlocks through the app with Touch ID.
2. Generate the vault key in 1Password:

   ```sh
   op item create --category=password --vault=Private --title=homelab-ansible-vault \
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
ansible-vault rekey inventory/host_vars/*/vault.yml        # after rotating the key in 1Password
```

Keep the key safe: anyone with it and repo access can decrypt every secret here. Losing it means re-creating the vault files. No 1Password at hand? `ansible-playbook site.yml --ask-vault-pass` prompts for the key instead.

## How nodes are addressed

By name only, never by IP: `ansible_host` is `<inventory_hostname>.<homelab_domain>`.

| `homelab_domain` | Resolves via | Works from |
|---|---|---|
| unset / `local` | mDNS (`k3s-01.local`) | home LAN only |
| `<tailnet>.ts.net` | Tailscale MagicDNS (`k3s-01.<tailnet>.ts.net`) | anywhere the laptop is on the tailnet |

Override for one run with `-e homelab_domain=local`.

## Roles

| Role | Does |
|---|---|
| `base` | Base packages; `cgroup_memory=1 cgroup_enable=memory` in `cmdline.txt` (k3s needs the memory cgroup); zram-only swap via rpi-swap (no swap file on the SD card); journald in RAM only, capped at 64M; unattended security upgrades (no auto-reboot). Reboots the node when the cmdline or swap config changes. |
| `tailscale` | Official apt repo, pinned `tailscale` (Renovate bumps it), `tailscaled` enabled; `tailscale up` with the node's inventory name, skipped once the node is up. |

## Tailscale

### First run (node not on the tailnet yet)

1. In the [admin console → Settings → Keys](https://login.tailscale.com/admin/settings/keys), generate an auth key: one-off (not reusable), not ephemeral.
2. Run over the LAN, passing the key at run time. The leading space keeps it out of shell history (zsh `setopt HIST_IGNORE_SPACE`, bash `HISTCONTROL=ignorespace`):

   ```sh
    TAILSCALE_AUTHKEY=tskey-auth-... ansible-playbook site.yml -e homelab_domain=local
   ```

   `-e tailscale_authkey=...` works too. The key is never logged (`no_log`) and only needed for the first login: later runs see the node is up and skip `tailscale up`.
3. In the [Machines](https://login.tailscale.com/admin/machines) page, open the node → **Disable key expiry**. Otherwise the node drops off the tailnet when its key expires (180 days by default).
4. Set `homelab_domain` in `local.yml` to the tailnet name (from the [DNS](https://login.tailscale.com/admin/dns) page), so later runs, `ssh` and kubectl go over the tailnet.

The node runs with `--accept-dns=false`: it never needs to resolve tailnet names, and this keeps its DNS (and so k3s CoreDNS) independent of `tailscaled`.

## Check

```sh
ansible-playbook site.yml                      # second run: changed=0
ssh k3s-01.local 'cat /sys/fs/cgroup/cgroup.controllers; cat /proc/swaps; ls /var/swap'
# expect "memory" in the controllers, only /dev/zram0 as swap, and no /var/swap

tailscale status                                 # k3s-01 listed, online
ssh k3s-01.<tailnet>.ts.net                      # also from outside home, e.g. phone hotspot
```
