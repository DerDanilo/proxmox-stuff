#!/bin/bash
# Version	      0.2.2 - BETA ! !
# Date		      02.20.2020
# Author 	      DerDanilo 
# Contributors    aboutte, xmirakulix, bootsie123

# set vars

# always exit on error
set -e

# permanent backups directory
# default value can be overridden by setting environment variable before running prox_config_backup.sh
# example: export BACKUP_DIR="/mnt/pve/media/backup
_bdir=${BACK_DIR:-/mnt/backups/proxmox}

# number of backups to keep before overriding the oldest one
MAX_BACKUPS=5

# temporary storage directory
_tdir=${TMP_DIR:-/var/tmp}

_tdir=$(mktemp -d $_tdir/proxmox-XXXXXXXX)

function clean_up {
    echo "Cleaning up"
    rm -rf $_tdir
}

# register the cleanup function to be called on the EXIT signal
trap clean_up EXIT

# Don't change if not required
_now=$(date +%Y-%m-%d.%H.%M.%S)
_HOSTNAME=$(hostname -f)
_filename1="$_tdir/proxmoxetc.$_now.tar"
_filename2="$_tdir/proxmoxpve.$_now.tar"
_filename3="$_tdir/proxmoxroot.$_now.tar"
_filename4="$_tdir/proxmox_backup_"$_HOSTNAME"_"$_now".tar.gz"

##########

function description {
    clear
    cat <<EOF

        Proxmox Server Config Backup
        Hostname: "$_HOSTNAME"
        Timestamp: "$_now"

        Files to be saved:
        "/etc/*, /var/lib/pve-cluster/*, /root/*"

        Backup target:
        "$_bdir"
        -----------------------------------------------------------------

        This script is supposed to backup your node config and not VM
        or LXC container data. To backup your instances please use the
        built in backup feature or a backup solution that runs within
        your instances.

        For questions or suggestions please contact me at
        https://github.com/DerDanilo/proxmox-stuff
        -----------------------------------------------------------------

        Hit return to proceed or CTRL-C to abort.

EOF
    read dummy
    clear
}

function are-we-root-abort-if-not {
    if [[ ${EUID} -ne 0 ]] ; then
      echo "Aborting because you are not root" ; exit 1
    fi
}

function check-num-backups {
    if [[ $(ls ${_bdir} -l | grep ^- | wc -l) -ge $MAX_BACKUPS ]]; then
      local oldbackup="$(ls ${_bdir} -t | tail -1)"
      echo "${_bdir}/${oldbackup}"
      rm "${_bdir}/${oldbackup}"
    fi
}

function copyfilesystem {
    echo "Tar files"
    # copy key system files
    tar --warning='no-file-ignored' -cvPf "$_filename1" /etc/.
    tar --warning='no-file-ignored' -cvPf "$_filename2" /var/lib/pve-cluster/.
    tar --warning='no-file-ignored' -cvPf "$_filename3" /root/.
}

function compressandarchive {
    echo "Compressing files"
    # archive the copied system files
    tar -cvzPf "$_filename4" $_tdir/*.tar

    # copy config archive to backup folder
    # this may be replaced by scp command to place in remote location
    cp $_filename4 $_bdir/
}

function stopservices {
    # stop host services
    for i in pve-cluster pvedaemon vz qemu-server; do systemctl stop $i ; done
    # give them a moment to finish
    sleep 10s
}

function startservices {
    # restart services
    for i in qemu-server vz pvedaemon pve-cluster; do systemctl start $i ; done
    # Make sure that all VMs + LXC containers are running
    qm startall
}

##########


description
are-we-root-abort-if-not
check-num-backups

# We don't need to stop services, but you can do that if you wish
#stopservices

copyfilesystem

# We don't need to start services if we did not stop them
#startservices

compressandarchive
