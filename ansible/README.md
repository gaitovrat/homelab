# Ansible

Bootstraps the k3s nodes. Run everything from this directory so `ansible.cfg` is picked up.

```sh
cd ansible
ansible-playbook site.yml -K          # -K prompts for the sudo password (BECOME password)
ansible-playbook site.yml -K --check  # dry run
```

Optional per-machine settings (SSH user, domain, sudo password source) go in `inventory/group_vars/all/local.yml`, which is gitignored; see `local.yml.example`.

## sudo password

sudo on the nodes asks for a password. Either:

- pass `-K` and type it each run, or
- let Ansible read it from 1Password, then drop `-K`:
  1. Install the CLI (`brew install 1password-cli`) and turn on 1Password → Settings → Developer → **Integrate with 1Password CLI**, so `op` unlocks through the app with Touch ID.
  2. In `local.yml`, set `ansible_become_password` to an `op read` lookup (commented example in `local.yml.example`). Get the `op://vault/item/field` path from the item's **Copy Secret Reference**.
  3. Check: `op read "op://…"` prints the password.

  The lookup runs `op read` on your machine whenever a task needs sudo; Touch ID is asked once per 1Password session. While it's set, `-K` is ignored (inventory variables beat command-line options); comment it out to go back to typing the password.

## How nodes are addressed

By name only, never by IP: `ansible_host` is `<inventory_hostname>.<homelab_domain>`, and `homelab_domain` defaults to `local` (mDNS, e.g. `k3s-01.local`, home LAN only). Override for one run with `-e homelab_domain=...`.

## Roles

| Role | Does |
|---|---|
| `base` | Base packages; `cgroup_memory=1 cgroup_enable=memory` in `cmdline.txt` (k3s needs the memory cgroup); zram-only swap via rpi-swap (no swap file on the SD card); journald in RAM only, capped at 64M; unattended security upgrades (no auto-reboot). Reboots the node when the cmdline or swap config changes. |

## Check

```sh
ansible-playbook site.yml -K                   # second run: changed=0
ssh k3s-01.local 'cat /sys/fs/cgroup/cgroup.controllers; cat /proc/swaps; ls /var/swap'
# expect "memory" in the controllers, only /dev/zram0 as swap, and no /var/swap
```
