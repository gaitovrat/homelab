# Ansible

Bootstraps the k3s nodes. Run everything from this directory so `ansible.cfg` is picked up.

```sh
cd ansible
ansible-playbook site.yml          # prompts for the sudo password (BECOME password)
ansible-playbook site.yml --check  # dry run
```

Optional per-machine settings (SSH user, domain) go in `inventory/group_vars/all/local.yml`, which is gitignored; see `local.yml.example`.

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
