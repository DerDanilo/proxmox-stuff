# Role: croit

Install Proxmox Mail Gateway Domain Mgmt Script

## Requirements

Supported Operating Systems:

* Any

Only `curl` and `bash` are required.

## Default Variables

domain_mgmt_script_path: "/opt/pmg_domain_mgmtdomain_mgmt.sh"
domain_mgmt_script_owner: "root"

## Example

```bash
ansible-playbook site.yml -l <INVENTORY_HOSTNAME> --tags pmg_domain_mgmtdomain_mgmt
```
