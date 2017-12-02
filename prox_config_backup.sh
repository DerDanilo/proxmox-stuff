#/bin/bash
# Version	0.1 - BETA ! !
# Date		30.11.2017
# Author 	DerDanilo

# set vars
_now=$(date +%Y-%m-%d.%H.%M.%S)
# temporary storage directory
_tdir="/var/tmp"
# permanent backups directory
_bdir="/mnt/backups/proxmox"

# Don't change if not required
_HOSTNAME=$(hostname -f)
_filename1="$_tdir/proxmoxetc.$_now.tar"
_filename2="$_tdir/proxmoxpve.$_now.tar"
_filename3="$_tdir/proxmoxroot.$_now.tar"
_filename4="$_tdir/proxmox_backup.$_HOSTNAME.$_now".tar.gz"



##########

function description {
clear
cat <<EOF

Proxmox Server Config Backup
Hostname: "$_HOSTNAME"
Timestamp: "$_now"

Files to be saved: 
"/etc/*, /var/lib/pve-cluster/*", /root/*"

Backup target:
"$_bdir"
-----------------------------------------------------------------

This script is supposed to backup your node config and not VM
or LXC container data. To backups your instances please use the 
build in backup feature or a backup soluiton that runs within 
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

function copyfilesystem {
# copy key system files
tar -cvf "$_filename1" /etc/*
tar -cvf "$_filename2" /var/lib/pve-cluster/*
tar -cvf "$_filename3" /root/*
}

function compressandarchive {
# archive the copied system files
tar -cvzf "$_filename4" $_tdir/*.tar && rm "$_filename1" && rm "$_filename2"

# copy config archive to backup folder
# this may be replaced by scp command to place in remote location
cp $_filename4 $_bdir/

# remove temp backup file
rm "$_filename4"
# remove backup leftovers
for f in "$_filename1" "$_filename2" "$_filename3" ; do rm $f ; done
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

# We don't need to stop services, but you can do that if you wish
#stopservices

copyfilesystem

# We don't need to start services if we did not stop them
#startservices

compressandarchive

