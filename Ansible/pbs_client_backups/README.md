# Role: pbs_client_backups

Deploys `proxmox-backup-client` backup scripts and cron jobs on Debian-based hosts.

> [!NOTE]
> This role is maintained on a **best-effort basis** and may not receive regular updates.
> It covers specific use cases and may require adaptation for your environment.

## Requirements

- Debian-based OS (Debian Bookworm or newer, Proxmox VE)
- `proxmox-backup-client` — no separate installation needed on PVE nodes,
  it ships with the default PVE package sources

## Default Variables

See [`defaults/main.yml`](defaults/main.yml) for the full list of defaults.

Key variables:

| Variable | Default | Description |
| --- | --- | --- |
| `pbs_repo_cleanup` | `false` | Remove old/conflicting PBS repo entries |
| `pbs_configure_repos` | `false` | Manage APT repo configuration |
| `pbs_install_packages` | `false` | Install packages (set `false` on running nodes to prevent unintended upgrades) |
| `pbs_client_backups_test_script` | `true` | Run a list-backup test after deployment |
| `pbs_client_backups_pbs_server` | `pbs.mydomain.de` | Default PBS server |
| `pbs_client_backups_pbs_datastore` | `DATASTORE_NAME` | Default datastore |
| `pbs_client_backups_default_cron_disabled` | `yes` | Cron disabled by default — enable per backup job |

## Usage

```bash
ansible-playbook site.yml -l <INVENTORY_HOSTNAME> --tags pbs_client_backups
```

## Example: Back up PVE cluster config from a standalone node

This example backs up `/etc/pve` (the Proxmox VE cluster/node configuration) to a PBS instance.
Useful for standalone PVE nodes where the built-in VM backup is handled separately.

```yaml
# Skip repo/package management — pbs client is already available on PVE
pbs_repo_cleanup: false
pbs_configure_repos: false
pbs_install_packages: false

pbs_client_backups_test_script: true

pbs_client_backups:
  - name: "pve-config-backup"
    source:
      - name: "pve-config"
        path: "/etc/pve"
    cron_disabled: "no"
    cron_minute: "17"
    cron_hour: "*/12"
    pbs_password: "{{ vault_pbs_password_pve_backup }}"
    pbs_user_string: "pvebackup@pbs"
    pbs_pbs_server: "{{ pbs_client_backups_pbs_ip_dc1_pbs01 }}"
    pbs_pbs_fingerprint: "{{ pbs_client_backups_pbs_fingerprint_dc1_pbs01 }}"
    pbs_pbs_datastore: "main"
    pbs_pbs_namespace: "pve"
```

Store the PBS password in an Ansible Vault file, e.g. `host_vars/mypvenode/vault.yml`:

```yaml
vault_pbs_password_pve_backup: "your-api-token-or-password"
```

Inventory variables for the PBS server address and fingerprint are typically defined
in `group_vars` or `host_vars`:

```yaml
pbs_client_backups_pbs_ip_dc1_pbs01: "192.168.1.10"
pbs_client_backups_pbs_fingerprint_dc1_pbs01: "AA:BB:CC:..."
```
