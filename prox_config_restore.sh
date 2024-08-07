#!/bin/bash
# Version	      0.2.4
# Date		      08.04.2024
# Author 	      razem-io 
# Contributors

# Very basic restore script based on https://github.com/DerDanilo/proxmox-stuff/issues/5

# Restores backup from prox_config_backup.sh
#   example: prox_config_restore.sh pve_proxmoxhostname_2023-12-02.15.48.10.tar.gz

set -e

if [[ $# -eq 0 ]] ; then
    echo 'Argument missing -> restore.sh pve_proxmoxhostname_2023-12-02.15.48.10.tar.gz'
    exit 0
fi

echo "Select restore mode:"
echo "1) Default restore"
echo "2) Restore with /etc/fstab commented out and saved as /etc/fstab_RESTORED"
read -p "Enter choice (1 or 2): " CHOICE

case "$CHOICE" in
    1)
        COMMENT_FSTAB=false
        ;;
    2)
        COMMENT_FSTAB=true
        echo "WARNING: Option 2 is experimental and may be suitable for new Proxmox systems."
        echo "A copy of the /etc/fstab file from your backup will be made, all lines will be commented out, and the copy and saved as /etc/fstab_RESTORED and moved to /etc."
        echo "It is your responsibility to make any necessary configuration updates to /etc/fstab based on /etc/fstab_RESTORED."
        read -p "Are you sure you want to proceed with this option? (y/n): " CONFIRMATION
        if [[ "$CONFIRMATION" != "y" && "$CONFIRMATION" != "Y" ]]; then
            echo "Option aborted. Exiting."
            exit 1
        fi
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

FOLDER_1="./$1_1"
FOLDER_2="./$1_2"

mkdir "$FOLDER_1"
mkdir "$FOLDER_2"

tar -zxvf $1 -C "$FOLDER_1"
find "$FOLDER_1" -name "*tar" -exec tar xvf '{}' -C "$FOLDER_2" \;

if [ "$COMMENT_FSTAB" = true ]; then
    echo "Processing /etc/fstab"
    if [[ -f "$FOLDER_2/etc/fstab" ]]; then
        sed 's/^/# /' "$FOLDER_2/etc/fstab" > /tmp/fstab_RESTORED
    fi
fi

for i in pve-cluster pvedaemon vz qemu-server; do systemctl stop $i ; done || true

if [ "$COMMENT_FSTAB" = true ] && [[ -f /tmp/fstab_RESTORED ]]; then
    mv /tmp/fstab_RESTORED /etc/fstab_RESTORED
else
    find "$FOLDER_2" -type f ! -name 'fstab_RESTORED' -exec cp -a '{}' / \;
fi

cp -avr "$FOLDER_2/" /

rm -r "$FOLDER_1" "$FOLDER_2" || true

if [ "$COMMENT_FSTAB" = true ] && [[ -f /tmp/fstab_RESTORED ]]; then
    rm /tmp/fstab_RESTORED
fi

read -p "Restore complete. Hit 'Enter' to reboot or CTRL+C to cancel."
reboot