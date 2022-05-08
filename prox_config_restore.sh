#!/bin/bash
# Version	      0.2.3
# Date		      04.18.2022
# Author 	      razem-io 
# Contributors

# Very basic restore script based on https://github.com/DerDanilo/proxmox-stuff/issues/5

# Restores backup from prox_config_backup.sh
#   example: prox_config_restore.sh proxmox_backup_proxmoxhostname_2017-12-02.15.48.10.tar.gz

set -e

if [[ $# -eq 0 ]] ; then
    echo 'Argument missing -> restore.sh proxmox_backup_proxmoxhostname_2017-12-02.15.48.10.tar.gz'
    exit 0
fi

FOLDER_1="./$1_1"
FOLDER_2="./$1_2"

mkdir "$FOLDER_1"
mkdir "$FOLDER_2"

tar -zxvf $1 -C "$FOLDER_1"
find "$FOLDER_1" -name "*tar" -exec tar xvf '{}' -C "$FOLDER_2" \;

for i in pve-cluster pvedaemon vz qemu-server; do systemctl stop $i ; done || true

cp -avr $FOLDER_2/. /

rm -r "$FOLDER_1" "$FOLDER_2" || true

read -p "Restore complete. Hit 'Enter' to reboot or CTRL+C to cancel."
reboot