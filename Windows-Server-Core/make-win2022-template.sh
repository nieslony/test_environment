#!/bin/bash

SHYAML=$( which shyaml )
if [ -z "$SHYAML" ]; then
    echo Please install shyaml

    exit 1
fi

VM_NAME="win2022-tmpl"
VM_RAM="2048"
VM_DISK_SIZE="32"
ADMIN_PASSWORD="$( shyaml get-value dc.admin_password < ../config.yml )"

INSTALL_ISO="$HOME/Downloads/SERVER_EVAL_x64FRE_en-us.iso"
DRIVER_ISO="/usr/share/virtio-win/virtio-win.iso"

CONFIG_ISO="$( mktemp -u /tmp/config_XXXXXX.iso )"
CONFIG_ISO_CONTENT="$( mktemp --directory /tmp/config_XXXXXX )"

INSTALL_ISO_TMP=$( mktemp )
cp -v $INSTALL_ISO $INSTALL_ISO_TMP
ls -l $INSTALL_ISO_TMP

export ADMIN_PASSWORD
export VM_NAME

function log {
    cols=$( tput cols )
    padding=$( eval printf -- '-%.0s' {1..${cols}} )
    msg="--- $(date) --- $@ $padding"
    eval echo "--- ${msg:0:${cols}} ---"
}

log Creating content of ISO
envsubst \
    < autounattend.xml \
    > $CONFIG_ISO_CONTENT/autounattend.xml
cp -v *.ps1 $CONFIG_ISO_CONTENT || exit 1
ls -l $CONFIG_ISO_CONTENT

log Creating config iso $CONFIG_ISO
mkisofs \
    -output "$CONFIG_ISO" \
    -input-charset utf-8 \
    -joliet -rational-rock \
    $CONFIG_ISO_CONTENT/* || exit 1

log Starting installation
virt-install \
    --name "$VM_NAME" \
    --ram "$VM_RAM" \
    --network default,model=virtio \
    --disk path="$VM_NAME.qcow2",device=disk,size="$VM_DISK_SIZE",bus=virtio,pool=default \
    --cdrom "$INSTALL_ISO_TMP" \
    --disk path="$DRIVER_ISO",device=cdrom \
    --disk path="$CONFIG_ISO",device=cdrom \
    --osinfo win2k22 || exit 1

true || (
virsh destroy --domain "$VM_NAME"
volumes=$(
    virsh domblklist --domain "$VM_NAME" --details |
    awk '/disk/ { print $NF; }'
)
virsh undefine --domain "windows2022.template"
for i in $volumes ; do
    rm -vf $i
done
)

rm -vf $INSTALL_ISO_TMP $CONFIG_ISO
