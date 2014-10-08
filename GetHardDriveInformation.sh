#!/bin/bash

DISKS=(`ls /dev/sd? | sed -e "s/\/dev\///g"`)

for i in ${DISKS[*]}; do
    disk=$i
    echo ""
    echo HDD Drive: "$disk"
    sudo smartctl --all /dev/$i | grep -i power_On
    ls -lai /dev/disk/by-label/ | grep -i $i
    ls -lai /dev/disk/by-id/ | grep -i $i
    fdisk -l | grep -i $i
done
