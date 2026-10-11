# Ansible

Bootstraps the k3s nodes. Run everything from this directory so `ansible.cfg` is picked up.

```sh
cd ansible
ansible-playbook site.yml          # all nodes, over Tailscale (Touch ID once, for the vault key)
ansible-playbook site.yml --check  # dry run
```

| Playbook | Reaches nodes via | Runs | When |
|---|---|---|---|
| `bootstrap.yml` | LAN, mDNS `<host>.local` | `tailscale` | once per new node, to get it onto the tailnet |
| `site.yml` | tailnet, MagicDNS name | everything | always after that |

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

The one exception is a new node, which isn't on the tailnet yet: `bootstrap.yml` sets `ansible_host: <host>.local` as a play var (play vars beat inventory), so it reaches the node over the LAN by mDNS and joins it to the tailnet (see [Tailscale first run](#first-run-node-not-on-the-tailnet-yet)).

Per-node overrides (e.g. `ansible_user`, if your SSH user differs from your local username) go in `host_vars/<host>/`.

## Roles

| Role | Does |
|---|---|
| `base` | Base packages; `cgroup_memory=1 cgroup_enable=memory` in `cmdline.txt` (k3s needs the memory cgroup); zram-only swap via rpi-swap (no swap file on the SD card); journald in RAM only, capped at 64M; unattended security upgrades (no auto-reboot). Reboots the node when the cmdline or swap config changes. |
| `tailscale` | Official apt repo, pinned `tailscale` (Renovate bumps it), `tailscaled` enabled; `tailscale up` with the node's inventory name, skipped once the node is up. |
| `disks` | Mounts the node's `disks_mounts` at `/mnt/disks/<name>` by filesystem UUID, whenever the disk is plugged in (see [Disks](#disks)); spins USB HDDs down after 10 min idle (`hd-idle`). Never formats anything. |

## Tailscale

### First run (node not on the tailnet yet)

1. In the [admin console → Settings → Keys](https://login.tailscale.com/admin/settings/keys), generate an auth key: **reusable** (one key onboards every node), **not ephemeral**, expiry up to 90 days, pre-approved if device approval is on, no tags.
2. Put it in the shared vault (creates the file the first time; `edit` afterwards), then commit the encrypted file:

   ```sh
   ansible-vault create inventory/group_vars/all/vault.yml   # tailscale_authkey: tskey-auth-...
   ```

3. Add the node to `inventory/hosts.yml` (and its `host_vars/<host>/vault.yml` with the sudo password), then bootstrap it from home, over the LAN:

   ```sh
   ansible-playbook bootstrap.yml --limit k3s-02
   ```

   The key is never logged (`no_log`) and only used for a node's first login: later runs see the node is up and skip `tailscale up`. When the key expires, nodes already on the tailnet are unaffected; generate a new one and `ansible-vault edit` it in before onboarding the next node. You can also revoke it in the console once all nodes have joined.
4. In the [Machines](https://login.tailscale.com/admin/machines) page, open the node → **Disable key expiry**. Otherwise the node drops off the tailnet when its key expires (180 days by default).
5. Check the node's name on the Machines page is exactly its inventory name (not `k3s-02-1`).
6. Run `ansible-playbook site.yml` for the rest (base OS, …), now over the tailnet. From here on `site.yml`, `ssh` and kubectl reach the node by its MagicDNS name.

The node runs with `--accept-dns=false`: it never needs to resolve tailnet names, and this keeps its DNS (and so k3s CoreDNS) independent of `tailscaled`.

## Disks

Each data disk is listed per node in `inventory/host_vars/<host>/main.yml`:

```yaml
disks_mounts:
  - name: hdd1                  # mounted at /mnt/disks/hdd1
    uuid: 0C5F-09C7             # filesystem UUID, from `lsblk -f`
    fstype: exfat               # default ext4
    options: noatime,uid=1000,gid=1000,fmask=0022,dmask=0022   # default noatime
```

A filesystem UUID is not a secret, so it lives in plain text. It changes only when the disk is reformatted.

### ext4 or exFAT

k3s-01's HDD is **exFAT**, so it can be unplugged and read on macOS or Windows as is. That's fine for plain files (FileBrowser, backups), with these trade-offs:

- **No Unix owners or permissions.** Every file shows the `uid`/`gid` and masks from the mount options (here 1000, the admin user, `rwxr-xr-x`). Pods that write to the disk must run as uid 1000; `chown`/`chmod` inside it fail or do nothing.
- **No journal.** A disk pulled out mid-write can be left inconsistent. The role installs `exfatprogs`, so `fsck.exfat` repairs it automatically next time it's mounted. Still, prefer `sudo systemctl stop mnt-disks-hdd1.mount` before unplugging.
- **No symlinks, hard links or special files.** So no k8s PVs for databases, and no `rsync -aHAX` onto it.

Use ext4 for a disk that only the Pi uses, or that needs any of the above.

### Unplugged or replaced disks

A data disk can be missing at any time, and nothing depends on it being there:

- **Not plugged in at boot:** boot doesn't wait for it. The disk gets a systemd mount unit (`mnt-disks-<name>.mount`) that nothing enables. A udev rule (`/etc/udev/rules.d/90-homelab-disks.rules`) starts that unit when a filesystem with its UUID appears, at boot or hot-plugged later. Ansible prints a warning and carries on.
- **Unplugged while running:** systemd unmounts it (the mount unit stops when its device goes away), so there's no stale mount. Plug it back in and it's fsck'd and mounted again.
- **Empty mountpoint:** while no disk is mounted, `/mnt/disks/<name>` is an empty, immutable (`chattr +i`) directory on the SD card. Writes there fail instead of quietly filling the SD card.
- **Spindown:** `hd-idle` applies to every `sd*` disk, not to one device name, so it covers a replacement disk with no changes.

Pods that use a disk through `hostPath` should set `mountPropagation: HostToContainer`. Without it, a pod keeps the mount it started with, and only a pod restart picks up a disk that was re-plugged.

To **add or replace** a disk, plug it into the Pi and read its UUID with `ssh k3s-01.tailbc9346.ts.net lsblk -f`. A disk already formatted exFAT (e.g. on a Mac, with Disk Utility → Erase → ExFAT, GUID scheme) needs nothing else. To format it on the Pi instead (this wipes it):

```sh
ssh k3s-01.tailbc9346.ts.net
lsblk -f                                                 # find the new disk, e.g. /dev/sdb; check it's the right one
echo 'type=linux' | sudo sfdisk --label gpt /dev/sdb     # one partition, whole disk
sudo mkfs.exfat -L Backup /dev/sdb1                      # or: sudo mkfs.ext4 -L hdd1 -m 0 /dev/sdb1
lsblk -f /dev/sdb                                        # copy the UUID
```

Put the UUID (and `fstype`/`options`) into `host_vars/<host>/main.yml` and run `ansible-playbook site.yml`. When an entry's UUID changes, the mount unit is restarted, so the new disk replaces the old one at the same path. Copy data over first if the old disk still works: mount the new disk somewhere temporary and `rsync -rt /mnt/disks/hdd1/ /mnt/new/` (`-rt`, since exFAT can't hold owners or links). Removing an entry from `disks_mounts` doesn't clean up its unit or mountpoint on the node; do that by hand.

## Check

```sh
ansible-playbook site.yml                      # second run: changed=0
ssh k3s-01.tailbc9346.ts.net 'cat /sys/fs/cgroup/cgroup.controllers; cat /proc/swaps; ls /var/swap'
# expect "memory" in the controllers, only /dev/zram0 as swap, and no /var/swap

tailscale status                               # k3s-01 listed, online

ssh k3s-01.tailbc9346.ts.net 'findmnt /mnt/disks/hdd1; systemctl is-active hd-idle'
# expect the disk mounted from /dev/sdX1; unplug it and findmnt is empty, and
# `lsattr -d /mnt/disks/hdd1` shows `i` on the bare mountpoint
```
