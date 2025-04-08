#!/bin/bash

BOX_NAME="ubuntu2404"
VM_NAME="$BOX_NAME-tmpl"
VM_RAM="2048"
VM_DISK_SIZE="32"
UBUNTU_VERSION="24.04.02"

ISO_FN="ubuntu-$UBUNTU_VERSION-live-server-amd64.iso"
ISO_URL="https://releases.ubuntu.com/$UBUNTU_VERSION/ubuntu-$UBUNTU_VERSION-live-server-amd64.iso"

function log {
    echo
    cols=$( tput cols )
    padding=$( eval printf -- '-%.0s' {1..${cols}} )
    msg="--- $(date) --- $@ $padding"
    eval echo "${msg:0:${cols}}"
}

function cleanup_template {
    log Cleanup
    if [ -n "$( virsh list --all --name | grep $VM_NAME )" ]; then
        volumes=$(
            virsh domblklist --domain "$VM_NAME" --details |
            awk '/disk/ { print $NF; }'
        )

        echo "Removing VM $VM_NAME"
        virsh undefine $VM_NAME

        for i in $volumes ; do
            echo "Removing volume $i"
            virsh vol-delete --pool default --vol $( basename $i )
        done
    else
        echo "VM $VM_NAME does not exist, no cleanup"
    fi
}

function cleanup_tmp_template_files {
    log "Removing Template TMP volumes"
    for disk in $INSTALL_ISO_TMP $CONFIG_ISO ; do
        echo -n "Removing $disk: "
        if [ -w "$disk" ]; then
            rm -vf $disk
        fi
        virsh detach-disk --domain "$VM_NAME" $disk --persistent --config
        virsh vol-delete --pool tmp $( basename $disk )
    done
    rm -rv "$CONFIG_ISO_CONTENT"
}

function cleanup_tmp_box_files {
    log "Cleanup box TMP files"
    if [ -e "$TMPL_IMAGE" ]; then
        rm -vf $TMPL_IMAGE
    fi
    if [ -d "$VAGRANT_TMP_DIR" ]; then
        rm -rvf "$VAGRANT_TMP_DIR"
    fi
    if [ -e "$INSTALL_ISO_TMP" ]; then
        rm -vf "$INSTALL_ISO_TMP"
    fi
}

function on_exit {
    log Cleanup on exit
    cleanup_template
    cleanup_tmp_box_files
}

trap on_exit EXIT

cleanup_template

log Starting setup

virt-install \
    --name $VM_NAME \
    --osinfo ubuntu-lts-latest \
    --memory 2048 \
    --vcpus 2 \
    --clock offset=utc \
    --cdrom https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-live-server-amd64.iso ---" \
    --network default,model=virtio \
    --disk path="$VM_NAME.qcow2",device=disk,size="$VM_DISK_SIZE",bus=virtio,pool=default
