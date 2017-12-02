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
_filename1="$_tdir/proxmoxetc.$_now.tar"
_filename2="$_tdir/proxmoxpve.$_now.tar"
_filename3="$_tdir/proxmoxroot.$_now.tar"
_filename4="$_tdir/$_HOSTNAME_proxmox_backup.$_now.tar.gz"

_HOSTNAME=$(hostname -f)

##########

function description {
clear
cat <<EOF

  Proxmox Server Config Backup

  Files to be saved: 
  "/etc/*, /var/lib/pve-cluster/*", /root/*"
  -----------------------------------------------------------------

  This backup script is only ment to run on machines where ALL 
  VMs/Containers are in status 'stopped' (not running anymore).
  Otherwise something probably will go terrible wrong and you 
  might loose valuable data!

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

function copyfilesystem {
# copy key system files
tar -cvf "$_filename1" /etc/*
tar -cvf "$_filename2" /var/lib/pve-cluster/*
tar -cvf "$_filename3" /root/*
}

function compressandarchive {
# archive the moved system file
tar -cvzf "$_filename4" $_tdir/*.tar && rm "$_filename1" && rm "$_filename2"
cd "$_tdir"

# Move config archive to backup folder
mv $_filename4 $_bdir/
}



##########


description
are-we-root-abort-if-not
#stopservices
copyfilesystem
#startservices
compressandarchive

