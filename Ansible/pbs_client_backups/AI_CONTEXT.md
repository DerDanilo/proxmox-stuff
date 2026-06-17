# pbs_client_backups — AI context

Context and invariants for AI assistants working on this role. Read this before
changing anything. Human-facing usage docs live in [`README.md`](README.md).

## Purpose

Render one Proxmox Backup *client* wrapper script per backup target, deploy
optional client-side encryption key files, and install matching cron jobs. The
scripts call `proxmox-backup-client backup …` and push to a PBS. Package
installation is NOT done here — that is the separate [`pbs`](../pbs/) role.

## Hard invariants — do NOT break these

1. **Per-target keys are an API.** Inventory files use these exact keys inside
   `pbs_client_backups` list items, including the historical double prefix:
   `pbs_pbs_server`, `pbs_pbs_server_port`, `pbs_pbs_fingerprint`,
   `pbs_pbs_datastore`, `pbs_pbs_namespace`, `pbs_password`, `pbs_user_string`,
   `pbs_encryption_password`, `pbs_encryption_keyfile`, plus `name`, `source`,
   `cron_*`. **Never rename them** — it silently breaks every host whose
   inventory already uses these keys.
2. **Secrets land on disk in cleartext.** The wrapper script embeds
   `PBS_PASSWORD` (API token) and possibly `PBS_ENCRYPTION_PASSWORD`. The
   directory and scripts MUST stay root-owned and `0700`, key files `0600`.
   Never widen these modes and never make the dir world-traversable.
3. **Never connect to managed hosts from this workstation.** Build, render and
   lint here only; rollout is done by the maintainer.
4. **The test phase must stay non-fatal and side-effect free.** It runs each
   script with no arguments (list mode only) under `failed_when: false` +
   `changed_when: false`. Do not let it run `--backup` or fail the play.
5. **`pbs_client_backups` defaults to `[]`.** Do not ship an active example
   entry as a default — a host that includes the role without defining targets
   must deploy nothing.

## Conventions (house style)

- Task names: **no role-name prefix** (per maintainer feedback, 2026-06). The
  role name is applied as a **tag** once at the `import_tasks` level in
  `main.yml`; static imports propagate tags to all imported tasks. Phase tags:
  `pbs_client_backups_{validate,deploy,test,cron}`.
- FQCN everywhere (`ansible.builtin.*`).
- `become: true` only on tasks that need root (everything except validation).
- Octal modes are quoted strings (`'0700'`) so YAML/ansible-lint stay happy.
- Booleans are `true`/`false` (yamllint `truthy`); cron `disabled`/`cron_*`
  intentionally keep the PBS-style `'yes'`/`'no'` string values.
- Docs and comments in English; chat with the maintainer in German.
- defaults file shows every optional value as a commented example.

## File map

- `tasks/main.yml` — orchestrator: import validate → deploy → test → cron, each
  carrying the `pbs_client_backups` tag + a phase tag.
- `tasks/validate.yml` — assert input shape (no become).
- `tasks/deploy.yml` — create `0700` dir, render scripts, decrypt key files.
- `tasks/test.yml` — connectivity check (list mode, non-fatal) + debug output.
- `tasks/cron.yml` — one cron entry per target.
- `tasks/prune.yml` — opt-in reconciliation (removes scripts + cron of targets
  no longer listed). Imported only when `pbs_client_backups_prune` is true AND
  the list is non-empty. Its desired-set includes BOTH `<base>_<name>.sh` and
  `<base>_<name>_mount.sh`, so mount helpers of live targets are not pruned.
- `templates/pbs_mount_script.sh.j2` — read-only FUSE mount helper
  (`<base>_<name>_mount.sh`, default on via `pbs_client_backups_deploy_mount_script`).
  Switches: status/list/mount/remount/umount. Its PBS connection block is a copy
  of the backup template's — update both together. An embedded python3 parser
  (written to a tmpfile) renders a numbered snapshot picker; falls back to the
  plain `snapshot list` if python3 is absent.
- `templates/pbs_backup_script.sh.j2` — the wrapper. Resolves every setting once
  at the top (`item.* | default(role_default, true)`), auto-brackets bare IPv6
  hosts, builds `PBS_REPOSITORY`, prints a summary, then lists or backs up.
- `defaults/main.yml` — all `pbs_client_backups_*` defaults + annotated example.

## Bandwidth limiting (key feature, verified facts)

- The script appends `--rate "<v>"` / `--burst "<v>"` to
  `proxmox-backup-client backup` only when the resolved value is non-empty.
- Value format is PBS **HumanByte**: `bytes/s` with optional unit. SI (`MB`) is
  base-10, binary (`MiB`) is base-2. Confirmed verbatim from the PBS 4.1
  `proxmox-backup-client(1)` synopsis: *"Rate limit (for Token bucket filter) in
  bytes/s with optional unit (B, KB (base 10), MB, GB, …, KiB (base 2), MiB,
  GiB, …)."* No minimum value.
- **Version caveat:** working HumanByte rate limiting requires the fix for
  [bug #5622](https://bugzilla.proxmox.com/show_bug.cgi?id=5622)
  (PBS ≥ 3.3 / 4.x). On older clients `--rate` is parsed as an integer and the
  limit is silently ignored. Trixie hosts ship a PBS 4.x client → fine.
- This is the **client-side** mechanism. Do NOT confuse it with the server-side
  `proxmox-backup-manager sync-job … --rate-in/--rate-out` (those throttle PBS
  *sync* jobs between datastores/archives, not client backups).
- **No thread/concurrency knob exists.** `proxmox-backup-client backup` has NO
  CLI option for parallel workers/threads/connections (verified against the PBS
  4.x synopsis + docs); chunk-upload parallelism is internal and fixed. Do not
  add a fake variable for it. `--rate`/`--burst` are the only client-side knobs.

## Jinja gotcha in the shell templates

Ansible renders with `trim_blocks=True` and the scripts are Bash, so two Bash
sequences collide with Jinja and must be avoided in the templates:
- `{%` `{{` `{#` — the bash array-length form `${#arr[@]}` contains `{#`
  (a Jinja comment opener) and breaks rendering. The mount template therefore
  uses a render-time `ARCHIVE_COUNT={{ item.source | length }}` instead.
- `trim_blocks` eats the newline after a closing `%}`; keep the blank line in
  the backup template before `__pbs_rc=$?` (see above).
Verify any template edit by rendering it offline before trusting it.

## Key design decisions / gotchas

- Resolution order is always **per-target key → role default** via
  `item.x | default(pbs_client_backups_x, true)`. The `true` makes an empty
  per-target value fall back to the default instead of staying empty.
- Namespace default is `''` (omit `--ns`), not a placeholder. A previous version
  had a typo'd default var `pbs_client_Backups_pbs_namespace` (capital B) and a
  placeholder `'NAMESPACE_NAME'`; both were fixed during the 2026-06 rework.
- Informational `proxmox-backup-client list` calls are suffixed with `|| true`
  so a first-ever run (namespace/snapshot not present yet) cannot abort the
  script before the actual backup.
- IPv6 server hosts must be written **bare** in inventory; the template adds the
  `[]` brackets. It strips any brackets the user added, then re-brackets the
  host iff it contains a colon (only IPv6 literals do; DNS/IPv4 never do).
- All values interpolated into the generated shell script go through the
  `quote` filter, so paths/namespaces/rate values with spaces or shell
  metacharacters cannot break the command or inject. The `--backup` dispatch is
  an exact match (`[ "$1" = "--backup" ]`), not a substring glob.
- The `--backup` path times the backup itself (`date +%s` before/after the
  command) and prints start/finish/duration (d/h/m/s). It measures wall clock
  rather than parsing the PBS client log — the client mixes a UTC "Starting
  backup" stamp with a local "Starting backup protocol"/"End Time", so epoch
  diff is the only TZ-safe option. The captured start equals the "Starting
  backup protocol" instant. The script then `exit`s with the backup command's
  real return code, so cron surfaces failures (list-mode runs still exit 0).
- **Jinja `trim_blocks` gotcha:** Ansible renders with `trim_blocks=True`, which
  eats the newline right after a closing `%}`. The backup command line ends in
  `{% endif %}{% endif %}`, so the line after it MUST be preceded by a blank
  line (or it merges onto the command). Keep the blank line before `__pbs_rc=$?`.
- **Additive lifecycle + opt-in prune:** by default the role only manages
  targets currently in `pbs_client_backups` and never removes anything.
  `pbs_client_backups_prune: true` enables `prune.yml`, which removes orphaned
  `pbs_client_backups_*.sh` scripts and `pbs_backup_*` cron entries. It is
  default-off and additionally guarded by `pbs_client_backups | length > 0`, so
  an empty/undefined list can never trigger mass deletion — keep both guards.
  Key files are deliberately NOT pruned (may be shared/global; harmless when
  orphaned, and the `*.sh` find pattern already excludes them).

## How to verify changes on this workstation

```bash
# Syntax + structure (no connection to targets)
ansible-playbook site.yml -l <host> \
  --tags pbs_client_backups --syntax-check

# List tasks and confirm tags propagate from the import level
ansible-playbook site.yml -l <host> --list-tasks

# Lint — expect only the project-baseline noise (name[casing], etc.)
ansible-lint roles/pbs_client_backups/

# Optional: render the Jinja template offline with sample vars to eyeball the
# generated --rate/--burst, IPv6 bracketing and namespace handling.
```
