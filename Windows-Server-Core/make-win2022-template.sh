#!/bin/bash

SHYAML=$( which shyaml )
if [ -z "$SHYAML" ]; then
    echo Please install shyaml

    exit 1
fi

BOX_NAME="win2022"
VM_NAME="$BOX_NAME-tmpl"
VM_RAM="2048"
VM_DISK_SIZE="32"
ADMIN_PASSWORD="$( shyaml get-value dc.admin_password < ../config.yml )"

INSTALL_ISO="$HOME/Downloads/SERVER_EVAL_x64FRE_en-us.iso"
# https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US
DRIVER_ISO="/usr/share/virtio-win/virtio-win.iso"

CONFIG_ISO="$( mktemp -u /tmp/config_XXXXXX.iso )"
CONFIG_ISO_CONTENT="$( mktemp --directory /tmp/config_XXXXXX )"

INSTALL_ISO_TMP=$( mktemp -u /tmp/install_XXXXXX.iso )

VAGRANT_TMP_DIR=$( mktemp --directory --tmpdir=/var/tmp )
VAGRANT_FILE=$VAGRANT_TMP_DIR/Vagrantfile
METADATA_FILE=$VAGRANT_TMP_DIR/metadata.json
BOX_FILE=$VAGRANT_TMP_DIR/$BOX_NAME.box

export ADMIN_PASSWORD
export VM_NAME

function log {
    echo
    cols=$( tput cols )
    padding=$( eval printf -- '-%.0s' {1..${cols}} )
    msg="--- $(date) --- $@ $padding"
    eval echo "${msg:0:${cols}}"
}

function cleanup_template {
    log Cleanup
    if [ -n "$( virsh list --all --name | grep win2022-tmpl )" ]; then
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
    log "Cleanup box TMP files from"
    if [ -e "$TMPL_IMAGE" ]; then
        rm -vf $TMPL_IMAGE
    fi
    if [ -d "$VAGRANT_TMP_DIR" ]; then
        rm -rvf "$VAGRANT_TMP_DIR"
    fi
}

function on_exit {
    cleanup_template
    cleanup_tmp_box_files
}

trap on_exit EXIT

cleanup_template

log "Copy Installer CD to $INSTALL_ISO_TMP"
cp -v $INSTALL_ISO $INSTALL_ISO_TMP
ls -l $INSTALL_ISO_TMP

log "Creating content of ISO"
envsubst \
    < autounattend.xml \
    > $CONFIG_ISO_CONTENT/autounattend.xml
cp -v *.ps1 $CONFIG_ISO_CONTENT || exit 1
ls -l $CONFIG_ISO_CONTENT

log "Creating config iso $CONFIG_ISO"
mkisofs \
    -output "$CONFIG_ISO" \
    -input-charset utf-8 \
    -joliet -rational-rock \
    $CONFIG_ISO_CONTENT/* || exit 1

log "Starting installation"
virt-install \
    --name "$VM_NAME" \
    --ram "$VM_RAM" \
    --network default,model=virtio \
    --disk path="$VM_NAME.qcow2",device=disk,size="$VM_DISK_SIZE",bus=virtio,pool=default \
    --cdrom "$INSTALL_ISO_TMP" \
    --disk path="$DRIVER_ISO",device=cdrom \
    --disk path="$CONFIG_ISO",device=cdrom \
    --osinfo win2k22 2> /dev/null || exit 1

cleanup_tmp_template_files

log Check Image
TMPL_IMAGE="$( virsh vol-path --pool default --vol $VM_NAME.qcow2 )"
if [ ! -e "$TMPL_IMAGE" ]; then
    echo "Image $TMPL_IMAGE does not exit"
    exit 1
fi

if [ ! -r "$TMPL_IMAGE" ]; then
    echo "Image $TMPL_IMAGE not readable, downloading to /var/tmp"
    TMPL_IMAGE="/var/tmp/$VM_NAME.qcow2"
    virsh vol-download --pool default --vol $VM_NAME.qcow2 --file $TMPL_IMAGE --sparse || exit 1
else
    echo "Image $TMPL_IMAGE exists and is readable"
fi

VIRTUAL_DISK_SIZE=$( qemu-img info $TMPL_IMAGE | awk '/virtual size/ { print $3; }' )
echo Virtual image size: ${VIRTUAL_DISK_SIZE}G

log Creating $METADATA_FILE
cat <<EOF > $METADATA_FILE
{
    "provider": "libvirt",
    "format": "qcow2",
    "virtual_size": $VIRTUAL_DISK_SIZE
}
EOF

log Creating $VAGRANT_FILE
cat <<EOF > $VAGRANT_FILE
Vagrant.configure("2") do |config|
    config.vm.communicator = "winrm"
    config.vm.guest = :windows
    config.vm.synced_folder ".", "/vagrant", disabled: true

    config.winrm.transport = :plaintext
    config.winrm.basic_auth_only = true
    config.winrm.username = "vagrant"
    config.winrm.password = "vagrant"
    config.winrm.ssl_peer_verification = false
    config.winrm.timeout = 120

    config.vm.provider :libvirt do |libvirt|
        libvirt.driver = "kvm"
        libvirt.host = 'localhost'
        libvirt.uri = 'qemu:///system'
        libvirt.connect_via_ssh = false
        libvirt.channel :type => 'unix',
            :target_name => 'org.qemu.guest_agent.0',
            :target_type => 'virtio'
        libvirt.channel :type => 'spicevmc',
            :target_name => 'com.redhat.spice.0',
            :target_type => 'virtio'
        libvirt.keymap = "de"
        libvirt.memory = 1024
        libvirt.cpus = 2
        libvirt.video_type = "qxl"
        libvirt.input :type => "mouse",
            :bus => "usb"
    end
end
EOF

log Creating $BOX_FILE
tar \
    --transform 's/.*qcow2/box.img/' \
    --transform 's/.*\///' \
    --create --file - \
    --sparse \
    --verbose \
    $METADATA_FILE $VAGRANT_FILE $TMPL_IMAGE \
    | pigz > $BOX_FILE || exit 1

log Removing existing box $BOX_NAME
if vagrant box list | grep -Eq "^$BOX_NAME " ; then
    vagrant box remove $BOX_NAME || exit 1
    virsh vol-delete --pool default --vol $VM_NAME.qcow2
else
    echo "There's no box $BOX_NAME to remove"
fi

log Creating new box $BOX_NAME
vagrant box add --name $BOX_NAME $BOX_FILE || exit 1

log Done.
