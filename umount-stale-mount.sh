#!/bin/bash
# Umount stale CIFS/SMB or NFS mounts after 300 seconds
# PVE will remount automatically if storage is activated

listsmb=$(mount | sed -n "s/^.* on \(.*\) type cifs .*$/\1/p")

for i in $listsmb ; do
        timeout 300 ls $i >& /dev/null
        if [ $? -ne 0 ] ; then
                echo "Stale $i"
                echo "Umount this stale mount"
                umount -f -l $i ;
        fi
done

listnfs=$(mount | sed -n "s/^.* on \(.*\) type nfs .*$/\1/p")

for i in $listnfs ; do
        timeout 300 ls $i >& /dev/null
        if [ $? -ne 0 ] ; then
                echo "Stale $i"
                echo "Umount this stale mount"
                umount -f -l $i ;
        fi
done
