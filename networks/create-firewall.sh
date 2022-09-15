#!/bin/bash

VM_NAME=gw.nieslony.lab
VM_RAM=512
VM_DISK_SIZE=8

INSTALL_ISO="$HOME/Downloads/pfSense-CE-2.6.0-RELEASE-amd64.iso"

TMP_ISO=$( mktemp )
cp -v $INSTALL_ISO $TMP_ISO

virt-install \
    --name "$VM_NAME" \
    --autostart \
    --network network=Lab_Internet,model=virtio \
    --network network=Lab_Windows_Internal,model=virtio \
    --network network=Lab_Linux_Internal,model=virtio \
    --disk path="$VM_NAME.qcow2",device=disk,size="$VM_DISK_SIZE",bus=virtio,pool=default \
    --cdrom "$TMP_ISO" \
    --osinfo freebsd9.2 \
    --memory $VM_RAM \
    --memballoon virtio \
    --graphics keymap=de \
    --channel type=unix,target.name=org.qemu.guest_agent.0,target.type=virtio \
    --channel type=spicevmc,target.name=com.redhat.spice.0,target.type=virtio \

rm -v $TMP_ISO
