#!/bin/bash
# Version	      0.2.3
# Date		      04.18.2022
# Author 	      DerDanilo 
# Contributors        aboutte, xmirakulix, bootsie123, phidauex

###########################
# Configuration Variables #
###########################

# Permanent backups directory
# Default value can be overridden by setting environment variable before running prox_config_backup.sh
#   example: export BACK_DIR="/mnt/pve/media/backup"
#   or
#   example: BACK_DIR="." ./prox_config_backup.sh
DEFAULT_BACK_DIR="/mnt/pve/media/backup"

# number of backups to keep before overriding the oldest one
MAX_BACKUPS=5

# Healthchecks.io notification service
# Set to 1 to use Healthchecks.io
HEALTHCHECKS=0
# Set to the URL of your healthchecks.io check
HEALTHCHECKS_URL=https://hc-ping.com/your_uuid_here

###########################

# Set terminal to "dumb" if not set (cron compatibility)
export TERM=${TERM:-dumb}

# always exit on error
set -e

# Set backup directory to default OR environment variable
_bdir=${BACK_DIR:-$DEFAULT_BACK_DIR}

# Check backup directory exists
if [[ ! -d "${_bdir}" ]] ; then
    echo "Aborting because backup target does not exists" ; exit 1
fi

# temporary storage directory
_tdir=${TMP_DIR:-/var/tmp}

_tdir=$(mktemp -d $_tdir/proxmox-XXXXXXXX)

function clean_up {
    exit_code=$?
    echo "Cleaning up"
    rm -rf $_tdir

    # Ping Healthchecks.io if enabled
    if [ $HEALTHCHECKS -eq 1 ]; then
        echo "Healthchecks.io notification is enabled"
        curl -fsS -m 10 --retry 5 -o /dev/null $HEALTHCHECKS_URL/${exit_code}
    fi
}

# register the cleanup function to be called on the EXIT signal
trap clean_up EXIT

# Don't change if not required
_now=$(date +%Y-%m-%d.%H.%M.%S)
_HOSTNAME=$(hostname -f)
_filename1="$_tdir/proxmoxetc.$_now.tar"
_filename2="$_tdir/proxmoxpve.$_now.tar"
_filename3="$_tdir/proxmoxroot.$_now.tar"
_filename4="$_tdir/proxmoxcron.$_now.tar"
_filename5="$_tdir/proxmoxvbios.$_now.tar"
_filename6="$_tdir/proxmoxpackages.$_now.list"
_filename7="$_tdir/proxmoxreport.$_now.txt"
_filename8="$_tdir/proxmoxlocalbin.$_now.tar"
_filename_final="$_tdir/proxmox_backup_"$_HOSTNAME"_"$_now".tar.gz"

##########

function description {
# Check to see if we are in an interactive terminal, if not, skip the description
    if [[ -t 0 && -t 1 ]]; then
        clear
        cat <<EOF

        Proxmox Server Config Backup
        Hostname: "$_HOSTNAME"
        Timestamp: "$_now"

        Files to be saved:
        "/etc/*, /var/lib/pve-cluster/*, /root/*, /var/spool/cron/*, /usr/share/kvm/*.vbios"

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
    fi
}

function are-we-root-abort-if-not {
    if [[ ${EUID} -ne 0 ]] ; then
      echo "Aborting because you are not root" ; exit 1
    fi
}

function check-num-backups {
    if [[ $(ls ${_bdir}/*${_HOSTNAME}*.tar.gz -l | grep ^- | wc -l) -ge $MAX_BACKUPS ]]; then
      local oldbackup="$(basename $(ls ${_bdir}/*${_HOSTNAME}*.tar.gz -t | tail -1))"
      echo "${_bdir}/${oldbackup}"
      rm "${_bdir}/${oldbackup}"
    fi
}

function copyfilesystem {
    echo "Tar files"
    # copy key system files
    tar --warning='no-file-ignored' -cvPf "$_filename1" --one-file-system /etc/.
    tar --warning='no-file-ignored' -cvPf "$_filename2" /var/lib/pve-cluster/.
    tar --warning='no-file-ignored' -cvPf "$_filename3" --one-file-system /root/.
    tar --warning='no-file-ignored' -cvPf "$_filename4" /var/spool/cron/.

    if [ "$(ls -A /usr/local/bin 2>/dev/null)" ]; then tar --warning='no-file-ignored' -cvPf "$_filename8" /usr/local/bin/.; fi

    if [ "$(ls /usr/share/kvm/*.vbios 2>/dev/null)" != "" ] ; then
	echo backing up custom video bios...
	tar --warning='no-file-ignored' -cvPf "$_filename5" /usr/share/kvm/*.vbios
    fi
    # copy installed packages list
    echo "Copying installed packages list from APT"
    apt-mark showmanual | tee "$_filename6"
    # copy pvereport output
    echo "Copying pvereport output"
    pvereport | tee "$_filename7"
}

function compressandarchive {
    echo "Compressing files"
    # archive the copied system files
    tar -cvzPf "$_filename_final" $_tdir/*.{tar,list,txt}

    # copy config archive to backup folder
    # this may be replaced by scp command to place in remote location
    cp $_filename_final $_bdir/
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
