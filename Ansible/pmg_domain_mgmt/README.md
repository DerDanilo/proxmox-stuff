# Role: pmg_domain_mgmt

Install Proxmox Mail Gateway Domain Mgmt Script

> [!NOTE]
> This role is shared as a **personal reference** and is not actively maintained on GitHub.
> It may not reflect the latest Proxmox versions or best practices. Use it as a starting point
> and adapt it to your environment.

## Requirements

Supported Operating Systems:

* Any (no guarantee!)

Only `curl` and `bash` are required.

## Default Variables

```yaml
domain_mgmt_script_path: "/opt/pmg_domain_mgmt.sh"
domain_mgmt_script_owner: "root"
```

## Example

```bash
ansible-playbook site.yml -l <INVENTORY_HOSTNAME> --tags pmg_domain_mgmt
```
