# Role: pbs_client_backups

Deploys **Proxmox Backup client** wrapper scripts, optional client-side
encryption key files and matching cron jobs. Each backup target gets its own
script under `/opt/backup_scripts/` that calls `proxmox-backup-client backup …`
and pushes data to a Proxmox Backup Server (PBS).

This role only *configures* backups. Installing the `proxmox-backup-client`
package is the job of the separate [`pbs`](../pbs/) role (`pbs_install_type: 'client'`).

> [!NOTE]
> This role is shared as a **personal reference**, not as a fully maintained
> open-source project. It was reworked **"vibe-coded"** — i.e. with substantial
> AI (LLM) assistance. There are no guarantees regarding update frequency or 
> compatibility with newer Proxmox versions. Treat it as a foundation to 
> **adapt to your own environment**, and review it before any production use.

> [!WARNING]
> Provided **as-is, without warranty of any kind**. Use at your own risk.

> AI assistants: read [`AI_CONTEXT.md`](AI_CONTEXT.md) before changing anything.

---

## What the role does

1. **validate** – fail fast if `pbs_client_backups` is malformed (each target
   needs `name` + `source`, each source needs `name` + `path`).
2. **deploy** – create `/opt/backup_scripts/` (root-only, `0700`), render one
   backup wrapper script per target (`0700`), a read-only **mount helper**
   (`<name>_mount.sh`, default on) and decrypt any encryption key files
   (`0600`).
3. **test** *(optional)* – run each script in list mode to verify
   connectivity/auth. Non-fatal and side-effect free.
4. **cron** – install one cron entry per target (created **disabled** by
   default; enable per target with `cron_disabled: 'no'`).
5. **prune** *(opt-in)* – with `pbs_client_backups_prune: true`, remove scripts
   and cron entries for targets no longer listed. See
   [Retiring or renaming a target](#retiring-or-renaming-a-target).

## Requirements

* Debian (tested on Bookworm / Trixie).
* `proxmox-backup-client` installed on the target (see the `pbs` role).
* The role escalates with `become` where root is required; run it as a sudo
  user, not as root.
* **Bandwidth limiting** (`pbs_rate` / `pbs_burst`) requires a PBS client
  `>= 3.3 / 4.x`. See [Bandwidth limiting](#bandwidth-limiting) below.

## Generated files

| Path | Mode | Content |
|------|------|---------|
| `/opt/backup_scripts/` | `0700` root | script directory |
| `/opt/backup_scripts/pbs_client_backups_<name>.sh` | `0700` root | wrapper script (contains the PBS token!) |
| `/opt/backup_scripts/pbs_client_backups_<keyfile>` | `0600` root | decrypted encryption key (if used) |
| crontab of `root` | – | `… pbs_client_backups_<name>.sh --backup` |

> **Security:** the wrapper scripts embed `PBS_PASSWORD` (API token) in
> cleartext, therefore directory and scripts are root-owned and `0700`/`0600`.
> Do not loosen these modes.

## Retiring or renaming a target

By default the role is **additive**: it only creates/updates artifacts for the
targets currently listed in `pbs_client_backups` and does **not** remove
artifacts for targets you delete or rename.

> ⚠️ A renamed/removed target whose old cron entry had `cron_disabled: 'no'`
> keeps firing backups under the old backup-id until it is removed.

### Option A — automatic prune (opt-in)

Set `pbs_client_backups_prune: true` (host/group var or `-e`). On the next run
the role removes any `pbs_client_backups_*.sh` script and any `pbs_backup_*`
cron entry that does not belong to a currently listed target:

```bash
ansible-playbook site.yml -l <host> --tags pbs_client_backups -e pbs_client_backups_prune=true
```

Safety: pruning is skipped entirely when `pbs_client_backups` is empty, so an
unset/empty list can never wipe all backups. Encryption **key files are never
auto-pruned** (they may be shared or global, and an orphaned key is harmless).

### Option B — manual cleanup

```bash
NAME=<old-target-name>
rm -f "/opt/backup_scripts/pbs_client_backups_${NAME}.sh"
crontab -l | grep -v "pbs_backup_${NAME}\b" | crontab -    # or: crontab -e
# plus any decrypted key file: /opt/backup_scripts/pbs_client_backups_<keyfile>
```

## Variables

### Backup targets — `pbs_client_backups`

A list of targets. Only `name` and `source` are required; every other key is
optional and falls back to the matching role default (resolution order:
**per-target key → role default**).

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `name` | ✅ | – | PBS backup-id |
| `source` | ✅ | – | list of archives (`name` + `path`, optional `includedev`) |
| `cron_disabled` | – | `pbs_client_backups_default_cron_disabled` (`'yes'`) | `'no'` to activate the cron entry |
| `cron_minute/hour/day/weekday/month` | – | `pbs_client_backups_default_cron_*` | schedule fields |
| `pbs_password` | – | `pbs_client_backups_pbs_password` | password / API token (use vault) |
| `pbs_user_string` | – | `pbs_client_backups_pbs_user_string` | `user@realm` or `user@realm!tokenid` |
| `pbs_pbs_server` | – | `pbs_client_backups_pbs_server` | DNS / IPv4 / bare IPv6 |
| `pbs_pbs_server_port` | – | `pbs_client_backups_pbs_server_port` (`8007`) | API port |
| `pbs_pbs_fingerprint` | – | `pbs_client_backups_pbs_fingerprint` | server cert fingerprint |
| `pbs_pbs_datastore` | – | `pbs_client_backups_pbs_datastore` | target datastore |
| `pbs_pbs_namespace` | – | `pbs_client_backups_pbs_namespace` (`''` = omit) | datastore namespace |
| `pbs_rate` | – | `pbs_client_backups_pbs_rate` (`''` = unlimited) | bandwidth limit (HumanByte) |
| `pbs_burst` | – | `pbs_client_backups_pbs_burst` (`''`) | token-bucket size (HumanByte) |
| `pbs_encryption_password` | – | `pbs_client_backups_pbs_encryption_password` | symmetric passphrase |
| `pbs_encryption_keyfile` | – | `pbs_client_backups_pbs_encryption_keyfile` | key file name (without `.vault`) |
| `mount_script` | – | `pbs_client_backups_deploy_mount_script` (`true`) | deploy the read-only mount helper |
| `pbs_mount_path` | – | `<mount_base>_<datastore>_<name>` | mount point for the helper |

> Note the historical double prefix on some keys (`pbs_pbs_server`,
> `pbs_pbs_fingerprint`, …). These names are an **API** used by existing
> inventories — do not rename them.

### Role defaults

See [`defaults/main.yml`](defaults/main.yml) — every variable is documented
inline with commented example values.

## Bandwidth limiting

The generated script appends `--rate` / `--burst` to
`proxmox-backup-client backup` when a limit is set. Values use the PBS
**HumanByte** format (`bytes/s` with an optional unit):

| Value | Meaning |
|-------|---------|
| `'90MB'` | 90 MB/s (base-10, = 90 000 000 B/s) |
| `'90MiB'` | 90 MiB/s (base-2, = 94 371 840 B/s) |
| `''` (empty) | unlimited (flag omitted) |

`--burst` sets the token-bucket size that allows short traffic bursts above the
sustained rate (also HumanByte).

> ⚠️ **Version requirement.** Working HumanByte rate limiting landed with the
> fix for [bug #5622](https://bugzilla.proxmox.com/show_bug.cgi?id=5622) and is
> available on `proxmox-backup-client` from **PBS ≥ 3.3 / 4.x**. On older
> clients the value is parsed as a raw integer and the limit is **silently
> ignored** (it does not error). All Trixie (Debian 13) hosts ship a PBS 4.x
> client and are fine.

## Usage

```bash
# Whole role for one host
ansible-playbook site.yml -l <host> --tags pbs_client_backups

# A single phase
ansible-playbook site.yml -l <host> --tags pbs_client_backups_deploy
ansible-playbook site.yml -l <host> --tags pbs_client_backups_cron
```

On the target, the generated script can be run by hand (as root):

```bash
/opt/backup_scripts/pbs_client_backups_<name>.sh            # list backups
/opt/backup_scripts/pbs_client_backups_<name>.sh --backup   # run a backup
```

### Backup output (timing & exit code)

`--backup` times the run itself (wall clock, time-zone safe) and prints a
summary; it then exits with the backup's real return code, so a failing backup
is visible to cron/monitoring (list-mode runs always exit 0):

```text
Backup started:  2026-06-11 20:41:03 CEST
Backup finished: 2026-06-11 22:25:38 CEST
Backup duration: 0d 01h 44m 35s (6275s total)
Result: SUCCESS (exit code 0).
```

## Read-only mount helper

Each target also gets `pbs_client_backups_<name>_mount.sh` (disable with
`mount_script: false`). It mounts a snapshot **read-only** via
`proxmox-backup-client mount` (FUSE). Run it as root:

```bash
M=/opt/backup_scripts/pbs_client_backups_<name>_mount.sh
"$M"                 # status: mount point + whether mounted
"$M" list            # compact, numbered list of available snapshots
"$M" mount           # interactive: pick a snapshot (and archive) to mount
"$M" mount 1         # mount snapshot #1 from the list (newest); no prompt
"$M" mount host/<name>/2026-06-11T18:41:03Z   # mount a specific snapshot id
"$M" remount 2       # unmount then mount snapshot #2
"$M" umount          # unmount and remove the (empty) mount point
```

* Default mount point: `<mount_base>_<datastore>_<name>`, e.g.
  `/mnt/backup_mydatastore_mybackup`. Override per target with
  `pbs_mount_path`, or globally via `pbs_client_backups_mount_base`.
* The interactive picker prints a numbered list (newest first) so you can choose
  which backup to inspect; you can also pass the snapshot id directly.
* For targets with several archives the helper asks which `*.pxar` to mount (or
  pass it as the 2nd argument). Encrypted backups reuse the same key file.
* The picker uses `python3` (present on managed hosts) to parse the snapshot
  list; without it, the helper falls back to the plain `snapshot list` and
  expects the snapshot id as an argument.

## Examples

### Minimal target (relies on group/role defaults for server, fingerprint, …)

```yaml
pbs_client_backups:
  - name: "etc"
    source:
      - name: "etc"
        path: "/etc"
    cron_disabled: 'no'
    cron_minute: '17'
    cron_hour: '*/12'
    pbs_password: '{{ vault_pbs_password_myhost }}'
    pbs_user_string: 'backup@pbs!{{ inventory_hostname }}'
    pbs_pbs_datastore: 'mydatastore'
    pbs_pbs_namespace: 'myproject'
```

### Full system backup with a bandwidth limit

```yaml
pbs_client_backups:
  - name: "fullsystem"                # PBS backup-id
    source:
      - name: "fullsystem"
        path: "/"
        includedev:                   # descend into these extra mountpoints
          - "/mnt/extra-disk"
    cron_disabled: 'no'
    cron_minute: '01'
    cron_hour: '1'
    pbs_password: '{{ vault_pbs_password_myhost }}'
    pbs_user_string: 'backup@pbs!{{ inventory_hostname }}'
    pbs_pbs_fingerprint: '{{ my_pbs_fingerprint }}'
    pbs_pbs_datastore: 'mydatastore'
    pbs_pbs_namespace: 'myproject'
    pbs_rate: '90MB'                  # limit upload to 90 MB/s
    # pbs_burst: '180MB'             # optional: allow short bursts
```

### Encrypted backup with a key file

The key is stored vault-encrypted next to the host vars as
`host_vars/<host>/<host>_encryption.key.vault` and decrypted onto the target.

```yaml
pbs_client_backups:
  - name: "encrypted"
    source:
      - name: "encrypted"
        path: "/"
        includedev:
          - "/srv/appdata"
    cron_disabled: 'no'
    pbs_password: '{{ vault_pbs_password_myhost }}'
    pbs_user_string: 'backup@pbs!{{ inventory_hostname }}'
    pbs_pbs_datastore: 'mydatastore'
    pbs_pbs_namespace: 'myproject'
    pbs_encryption_keyfile: '{{ inventory_hostname }}_encryption.key'
    # or a symmetric passphrase instead of a key file:
    # pbs_encryption_password: '{{ vault_pbs_encryption_password_myhost }}'
```

### Multiple targets on one host

```yaml
pbs_client_backups:
  - name: "etc"
    source: [{ name: "etc", path: "/etc" }]
    cron_disabled: 'no'
    cron_hour: '2'
    pbs_pbs_datastore: 'mydatastore'
  - name: "data"
    source: [{ name: "data", path: "/srv/data" }]
    cron_disabled: 'no'
    cron_hour: '3'
    pbs_pbs_datastore: 'mydatastore'
    pbs_rate: '50MiB'
```

## See also

* [`pbs`](../pbs/) – installs the `proxmox-backup-client` package and repos.
* [`AI_CONTEXT.md`](AI_CONTEXT.md) – invariants and design notes for maintainers/AI.
