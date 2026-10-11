# Ansible

Bootstraps the k3s nodes. Run everything from this directory so `ansible.cfg` is picked up.

```sh
cd ansible
ansible-playbook site.yml          # Touch ID once, for the vault key
ansible-playbook site.yml --check  # dry run
```

Per-node settings go in `inventory/host_vars/<host>/`: plain values in any `.yml` there, and secrets or anything that shouldn't be public in its encrypted `vault.yml` (see below).

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

By name only, never by IP. `ansible_host` defaults to `<inventory_hostname>.local` (mDNS, e.g. `k3s-01.local`, home LAN only), set in `group_vars/all/main.yml`. To reach a node another way, set `ansible_host` in its `host_vars/<host>/`, in `vault.yml` if the name shouldn't be public. For one run: `-e ansible_host=...` (with `--limit <host>`).

If your SSH user differs from your local username, set `ansible_user` the same way.

## Roles

| Role | Does |
|---|---|
| `base` | Base packages; `cgroup_memory=1 cgroup_enable=memory` in `cmdline.txt` (k3s needs the memory cgroup); zram-only swap via rpi-swap (no swap file on the SD card); journald in RAM only, capped at 64M; unattended security upgrades (no auto-reboot). Reboots the node when the cmdline or swap config changes. |

## Check

```sh
ansible-playbook site.yml                      # second run: changed=0
ssh k3s-01.local 'cat /sys/fs/cgroup/cgroup.controllers; cat /proc/swaps; ls /var/swap'
# expect "memory" in the controllers, only /dev/zram0 as swap, and no /var/swap
```
