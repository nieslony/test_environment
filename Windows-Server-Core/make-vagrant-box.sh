#!/bin/bash

VM_NAME="win2022-tmpl"
BOX_NAME="win2022"
POOL_NAME="default"

POOL_PATH=$( virsh pool-dumpxml --pool $POOL_NAME | xmllint --xpath 'string(/pool/target/path)' - )
IMAGE=$POOL_PATH/$VM_NAME.qcow2
if [ ! -e "$IMAGE" ]; then
    echo Image $IMAGE not found.
    exit 1
fi

VIRTUAL_SIZE=$( qemu-img info $IMAGE | awk '/virtual size/ { print $3; }' )

TMP_DIR=$( mktemp --directory --tmpdir=/var/tmp )
VAGRANT_FILE=$TMP_DIR/Vagrantfile
METADATA_FILE=$TMP_DIR/metadata.json
BOX_FILE=$TMP_DIR/$BOX_NAME.box

echo Creating $METADATA_FILE
cat <<EOF > $METADATA_FILE
{
    "provider": "libvirt",
    "format": "qcow2",
    "virtual_size": $VIRTUAL_SIZE
}
EOF

echo Creating $VAGRANT_FILE
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

echo Creating $BOX_FILE
if [ -r "$IMAGE_" ]; then
    echo file $IMAGE is not readable, exporting to temp file

    TMP_IMAGE=$( mktemp /var/tmp/$VM_NAME.qcow2.XXXXXX)
    virsh vol-download --pool default $VM_NAME.qcow2 /dev/stdout \
        > $TMP_IMAGE
#    \
#        | dd conv=sparse status=progress \
    IMAGE=$TMP_IMAGE
fi
tar \
    --transform 's/.*qcow2/box.img/' \
    --transform 's/.*\///' \
    --create --file - \
    --sparse \
    --verbose \
    $TMP_DIR/metadata.json $TMP_DIR/Vagrantfile $IMAGE \
    | pigz > $BOX_FILE || exit 1

if [ -n "TMP_IMAGE" ]; then
    rm -v $TMP_IMAGE
fi

echo Removing existing box $BOX_NAME
vagrant box remove $BOX_NAME

echo Creating new box $BOX_NAME
vagrant box add --name $BOX_NAME $BOX_FILE || exit 1
