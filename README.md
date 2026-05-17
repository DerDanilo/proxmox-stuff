# proxmox-stuff

A collection of scripts and Ansible roles for Proxmox administration (PVE/PMG/PBS).

> [!NOTE]
> This repository is shared as a **personal reference**, not as a fully maintained open-source project.
> The code reflects real configurations that were used in production environments at some point, but there
> are no guarantees regarding update frequency, compatibility, or long-term support. Please treat everything
> here as a foundation to build upon and adapt to your own environment. Pull requests are welcome, although
> responses or reviews may sometimes take a while.
>
> Over time, my motivation to maintain large amounts of reusable boilerplate infrastructure code has simply
> become smaller. AI-assisted development has changed a lot about how infrastructure and automation projects
> are approached today — in many cases, a good prompt and a clear understanding of your own environment are
> more valuable than digging through someone else's partially maintained repository.
>
> Beyond that, time is limited. Family and personal life naturally take priority, and I prefer spending the
> remaining hobby time actually building and experimenting with things instead of continuously polishing and
> maintaining GitHub repositories.

> [!WARNING]
> **No warranty, no liability — for anything in this repository.**
>
> Everything here is provided as-is, without any warranty of any kind, express or implied.
> Use it at your own risk. The authors and contributors are not responsible for any data loss,
> downtime, broken systems, or damage of any kind resulting from the use of this code.

---

## Ansible

Small role collection for Proxmox-related automation.

| Role | Description |
| --- | --- |
| `pbs` | Proxmox Backup Server setup |
| `pbs_client_backups` | Configure PBS client backups on PVE nodes |
| `pve` | Proxmox VE base setup |
| `pmg` | Proxmox Mail Gateway setup |
| `pmg_domain_mgmt` | PMG domain management |

See [Ansible/](Ansible/) for individual role READMEs.

---

## PVE Config Backup & Restore

Scripts to back up and restore the **node configuration** of a standalone Proxmox VE host.

> [!CAUTION]
> **Read before you run anything.**
>
> - These scripts back up **node configuration only** — not VM/LXC disk images or container data.
> - **Always restore on the same node and the exact same Proxmox VE version** you backed up from.
>   Restoring onto a different PVE version or a freshly installed system of a different version **might break your installation**.
> - **Clusters are not supported.** Running the restore script on a cluster node will corrupt the cluster state.
>   If you are running a cluster, do not use these scripts.
> - The restore script stops core PVE services and overwrites system files. **There is no undo.**
>   Make sure you have console access before running it.

### Quick Start (Installer)

The installer clones the repository, asks a few questions, and sets up the cron job for you.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DerDanilo/proxmox-stuff/master/pve_backup_and_restore/install.sh)
```

Or if you already have the repo:

```bash
bash /root/proxmox-stuff/pve_backup_and_restore/install.sh
```

The installer will:

1. Clone or update the repository to `/root/proxmox-stuff`
2. Ask for the backup target directory
3. Ask how many backups to retain
4. Optionally create a monthly cron job at `/etc/cron.monthly/proxmox-config-backup`

### Manual Setup

```bash
# Clone the repository
git clone https://github.com/DerDanilo/proxmox-stuff /root/proxmox-stuff

# Make scripts executable
chmod +x /root/proxmox-stuff/pve_backup_and_restore/prox_config_backup.sh
chmod +x /root/proxmox-stuff/pve_backup_and_restore/prox_config_restore.sh

# Run the backup (adjust BACK_DIR to your storage)
BACK_DIR="/mnt/pve/media/backup" /root/proxmox-stuff/pve_backup_and_restore/prox_config_backup.sh
```

### What Gets Backed Up

| Path | Description |
| --- | --- |
| `/etc/` | System configuration |
| `/etc/pve/` | Proxmox VE configuration (explicit, separate archive) |
| `/var/lib/pve-cluster/` | Cluster/node database |
| `/var/lib/vz/snippets/` | Hook scripts, cloud-init snippets (if non-empty) |
| `/var/spool/cron/` | Cron jobs |
| `/root/` | Root home directory |
| `/usr/local/bin/` | Local scripts/binaries (if non-empty) |
| `/usr/share/kvm/*.vbios` | Custom GPU vBIOS files (if present) |
| `/opt/` | Optional — set `BACKUP_OPT_FOLDER=true` |
| APT package list | Output of `apt-mark showmanual` |
| `pvereport` | Full `pvereport` output as text file |

The resulting archive is a compressed `.tar.gz`, typically 1–5 MB.

### Configuration

Configuration variables are at the top of `pve_backup_and_restore/prox_config_backup.sh`.
They can also be overridden via environment variables at runtime.

| Variable | Default | Description |
| --- | --- | --- |
| `BACK_DIR` / `DEFAULT_BACK_DIR` | `/mnt/pve/media/backup` | Target directory for backup archives |
| `MAX_BACKUPS` | `5` | Number of backups to keep per host |
| `BACKUP_OPT_FOLDER` | `false` | Include `/opt/` in backup |
| `HEALTHCHECKS` | `0` | Enable healthchecks.io ping (`1` = on) |
| `HEALTHCHECKS_URL` | — | Your healthchecks.io check URL |
| `TMP_DIR` | `/var/tmp` | Directory for temporary files during backup |

> [!NOTE]
> If you want to back up PVE cluster/node configuration to a Proxmox Backup Server, the
> [Ansible role `pbs_client_backups`](Ansible/pbs_client_backups/README.md) is the better fit.
> It has been used in production across many clusters for years, primarily backing up `/etc/pve`
> (the PVE cluster config). The role is extensible to individual node configs as well, though
> in practice a solid IaC setup often makes per-node config backups redundant — your Ansible
> inventory *is* the documentation. That said, nothing replaces clear, well-maintained docs.
> The role is shared on a best-effort basis and may not receive regular updates.

**Examples:**

```bash
# Override backup directory for this run only
BACK_DIR="/mnt/nas/proxmox-backups" ./prox_config_backup.sh

# Set permanently via environment
export BACK_DIR="/mnt/nas/proxmox-backups"
./prox_config_backup.sh
```

### Cron Setup

Create `/etc/cron.monthly/proxmox-config-backup`:

```bash
#!/bin/bash
BACK_DIR="/mnt/pve/media/backup" MAX_BACKUPS=5 /root/proxmox-stuff/pve_backup_and_restore/prox_config_backup.sh
```

Make it executable:

```bash
chmod +x /etc/cron.monthly/proxmox-config-backup
```

Test without actually waiting for the next month:

```bash
run-parts -v --test /etc/cron.monthly
run-parts -v /etc/cron.monthly
```

### Restore

> [!CAUTION]
> **Only restore on the same node and the same Proxmox VE version.**
> Restoring onto a different version will likely break your installation.
> Have console (IPMI/iDRAC/iKVM) access ready before you start.

```bash
/root/proxmox-stuff/pve_backup_and_restore/prox_config_restore.sh pve_myhostname_2026-05-17.12.00.00.tar.gz
```

The script stops PVE services, restores all files, and prompts for a reboot.

**Restore modes:**

| Mode | Description |
| --- | --- |
| 1 — Default | Full restore, `/etc/fstab` is overwritten as-is |
| 2 — fstab safe | `/etc/fstab` from the backup is commented out and saved as `/etc/fstab_RESTORED`. Use this when restoring onto a different disk layout. |

After a mode-2 restore, review `/etc/fstab_RESTORED` and update `/etc/fstab` manually before rebooting.

### Known Issues & Gotchas

These are real problems that have come up in the past — either fixed by patches or still worth being aware of.

#### Hostname collision in cleanup

**Problem:** If you have two nodes named `pve` and `pve2`, the backup rotation on `pve2` could accidentally delete backups from `pve` because the hostname pattern was not anchored.

**Status:** Fixed. The cleanup uses a pattern `*_${HOSTNAME}_*.tar.gz` which includes underscores as delimiters. If you renamed a node, old backups with the old hostname will not be rotated automatically — delete them manually.

#### MAX_BACKUPS not reducing existing backups

**Problem:** Lowering `MAX_BACKUPS` from e.g. 10 to 3 would not immediately prune existing backups down to 3 — only one extra backup would be deleted per run.

**Status:** Fixed. The cleanup now removes all backups beyond the limit in a single pass.

#### Backup archive explodes in size (`/tmp` fills up)

**Problem:** If a mount point lives inside a backed-up directory, `tar` would descend into it and include all data, causing `/tmp` to fill up and the backup to fail or become huge.

**Status:** Fixed via `--one-file-system` flag on all tar operations. Mounts are not followed.

#### Unsafe cleanup of backup directory

**Problem:** An older version of the cleanup function would delete *any* file in the backup directory when rotating, not just `.tar.gz` files matching the expected pattern.

**Status:** Fixed. Cleanup only touches files matching `*_${HOSTNAME}_*.tar.gz`.

#### Restoring `/etc/fstab` on a different disk layout

**Problem:** Restoring `/etc/fstab` from a backup onto a newly installed system with different disk UUIDs or device names will prevent the system from booting.

**Status:** Addressed by restore mode 2 (fstab safe). Use mode 2 whenever you are unsure whether your disk layout matches the backup.

#### Restore fails after PVE version upgrade

**Problem:** Restoring a backup from PVE 7 onto PVE 8 (or any cross-version restore) will overwrite `/etc/apt/sources.list`, `/etc/network/interfaces`, and other files with old content. This can break the system in subtle and non-obvious ways.

**Status:** Not fixable by the scripts. **Never restore across PVE versions.** If you need to migrate to a new PVE version, do a clean install and reconfigure manually, or restore and then re-run the PVE upgrade procedure.

#### Cluster nodes

**Problem:** On a cluster node, `/var/lib/pve-cluster/` contains the cluster database. Restoring it on one node while the others are running will corrupt the cluster.

**Status:** Not supported. These scripts are designed for standalone (non-clustered) nodes only.

#### Script fails silently in cron (exit on error)

**Problem:** `set -e` causes the script to exit on any error. In cron, without a mail setup, failures are silent.

**Mitigation:** Use [healthchecks.io](https://healthchecks.io) integration (`HEALTHCHECKS=1`) to get notified when the backup does not complete successfully. Alternatively, redirect cron output to a log file:

```bash
BACK_DIR="/mnt/pve/media/backup" /root/proxmox-stuff/pve_backup_and_restore/prox_config_backup.sh >> /var/log/proxmox-backup.log 2>&1
```
