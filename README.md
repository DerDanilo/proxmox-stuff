# Proxmox stuff
This is a collection of stuff that I wrote for Proxmox.

[TOC]

---

## Ansible

Small Ansible playbook and role collection for Proxmox related stuff.

## prox_config_backup

I just wrote this script quick and dirty.
Some people use it on a daily basis (including me).

There might be a PBS backup feature to backup PVE cluster config in the near future provided by the Proxmox team.
But since this was only mentioned on the roadmap we still have to wait.

Meanwhile I manage all PVE nodes with Ansible and usually have no need to restore configuration unless all cluster
nodes failed at once. But having a full cluster config backup is still useful and makes PVE admins sleep well at night (or day).

The script must be run as root, and can be run from cron or an interactive terminal.

### Backup
* Download the [script](https://raw.githubusercontent.com/DerDanilo/proxmox-stuff/master/prox_config_backup.sh)  
```cd /root/; wget -qO- https://raw.githubusercontent.com/DerDanilo/proxmox-stuff/master/prox_config_backup.sh```
* Set the permanent backups directory environment variable ```export BACK_DIR="/path/to/backup/directory"``` or edit the script to set the `$DEFAULT_BACK_DIR` variable to your preferred backup directory
* Make the script executable ```chmod +x ./prox_config_backup.sh```
* Shut down ALL VMs + LXC Containers if you want to go the safe way. (Not required)
* Run the script ```./prox_config_backup.sh```

### Restore
#### Manually

On my machine, you end up with a GZipped file of about 1-5 MB with a name like "proxmox_backup_proxmoxhostname_2017-12-02.15.48.10.tar.gz".  
Depending upon how you schedule it and the size of your server, that could eventually become a space issue so don't  
forget to set up some kind of archive maintenance.

To restore, move the file back to proxmox with cp, scp, webmin, a thumb drive, whatever.  
I place it back into the /var/tmp directory from where it came. 

```
# Unpack the original backup
tar -zxvf proxmox_backup_proxmoxhostname_2017-12-02.15.48.10.tar.gz
# unpack the tared contents
tar -xvf proxmoxpve.2017-12-02.15.48.10.tar
tar -xvf proxmoxetc.2017-12-02.15.48.10.tar
tar -xvf proxmoxroot.2017-12-02.15.48.10.tar

# If the services are running, stop them:
for i in pve-cluster pvedaemon vz qemu-server; do systemctl stop $i ; done

# Copy the old content to the original directory:
cp -avr /var/tmp/var/tmp/etc /etc
cp -avr /var/tmp/var/tmp/var /var
cp -avr /var/tmp/var/tmp/root /root

# And, finally, restart services:
for i in qemu-server vz pvedaemon pve-cluster; do systemctl start $i ; done
```

If nothing goes wrong, and you have separately restored the VM images using the default Proxmox process.  
You should be back where you started. But let's hope it never comes to that.


#### Script

* Download the [script](https://raw.githubusercontent.com/DerDanilo/proxmox-stuff/master/prox_config_restore.sh)  
```cd /root/; wget -qO- https://raw.githubusercontent.com/DerDanilo/proxmox-stuff/master/prox_config_restore.sh```
* Make the script executable ```chmod +x ./prox_config_restore.sh```
* Run the script ```./prox_config_restore.sh proxmox_backup_proxmoxhostname_2017-12-02.15.48.10.tar.gz```

### Notification

The script supports [Healthcheck.io](https://healthcheck.io) notifications, either to the hosted service, or a self-hosted instance. The notification sends during the final cleanup stage, and either returns 0 to tell Healthchecks that the command was successful, or the exit error code (1-255) to tell Healthchecks that the command failed. To enable:
* Set the `$HEALTHCHECK` variable to 1
* Set the `$HEALTHCHECK_URL` variable to the full ping URL for your check. Do not include anything after the UUID, the status flag will be added by the script.

### Sources
http://ziemecki.net/content/proxmox-config-backups
