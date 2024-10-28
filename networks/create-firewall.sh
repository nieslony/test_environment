#!/bin/bash

VM_NAME=gw.nieslony.lab
VM_RAM=512
VM_DISK_SIZE=8

DOWNLOAD_URL="https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.6.0-RELEASE-amd64.iso.gz"
INSTALL_ISO="$HOME/Downloads/$( basename -s .gz $DOWNLOAD_URL )"

shopt -s extglob

function my_sleep {
    REMAINING_SECS=$1
    shift
    MSG="$@"
    while [ $REMAINING_SECS -gt 0 ]; do
        echo -en "--- $MSG $REMAINING_SECS secs \r"
        REMAINING_SECS=$(( $REMAINING_SECS -1 ))
        sleep 1
    done
    echo
}

function log {
    echo "--- $@"
}

function send_key {
    SLEEP=""
    MSG=""
    while [ "${1:0:1}" == "-" ]; do
        case "$1" in
            "-s")
                shift
                SLEEP=$1
                ;;
            "-m")
                shift
                MSG="($1)"
                ;;
        esac
        shift
    done
    key="$@"
    echo -n "Sending key $key ... $MSG"
    virsh send-key $VM_NAME KEY_$key || exit 1
    if [ -n "$SLEEP" ]; then
        sleep $SLEEP
    fi
}

function send_string {
    SLEEP=""
    MSG=""
    while [ "${1:0:1}" == "-" ]; do
        case "$1" in
            "-s")
                shift
                SLEEP=$1
                ;;
            "-m")
                shift
                MSG="($1)"
                ;;
        esac
        shift
    done

    string="$1"
    echo "Sending string $string $MSG"
    length=${#string}
    for ((i = 0; i < length; i++)); do
        char="${string:i:1}"
        case "$char" in
            " ")
                char="KEY_SPACE"
                ;;
            "-")
                char="KEY_MINUS"
                ;;
            ".")
                char="KEY_DOT"
                ;;
            [a-z])
                char="KEY_${char^^}"
                ;;
            [A-Z])
                char="KEY_LEFTSHIFT KEY_${char^^}"
                ;;
            [0-9])
                char="KEY_$char"
                ;;
            *)
                echo "Invalid character: $char"
                exit 1
                ;;
        esac
        virsh send-key $VM_NAME $char > /dev/null || exit 1
    done
    virsh send-key $VM_NAME KEY_ENTER > /dev/null
    if [ -n "$SLEEP" ]; then
        sleep $SLEEP
    fi
}

if [ ! -e $INSTALL_ISO ]; then
    INSTALL_ISO_GZ="$INSTALL_ISO.gz"
    if [ ! -e $INSTALL_ISO_GZ ]; then
        (
            cd $HOME/Downloads
            wget $DOWNLOAD_URL
        )
    fi
    gunzip $INSTALL_ISO_GZ
fi

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
    --clock offset=utc \
    --channel type=unix,target.name=org.qemu.guest_agent.0,target.type=virtio \
    --channel type=spicevmc,target.name=com.redhat.spice.0,target.type=virtio \
    > /dev/null 2>&1 | grep -v GSpice-WARNING &

my_sleep 60 "Booting installer..."
for key in ENTER ENTER ENTER ENTER ENTER ENTER SPACE ENTER LEFT ENTER ; do
    send_key $key
    sleep 1
done

my_sleep 60 "Installing pfSense..."
send_key ENTER
send_key ENTER

my_sleep 60 "Rebooting..."

log "Assign interfaces"
send_string -m "Dont't configure vlans" n
send_string -m "Configure WAN interface" vtnet0
send_string -m "Configure LAN interface" vtnet1
send_string -m "Configure LAN interface" vtnet2
send_string -m "Confirm reboot" y

my_sleep 60 "Rebooting with configured interfaces..."

log "Configure Windows_LAB"
send_string -m "Set interface IP" 2
send_string -m "Select Windows_LAB" 2
send_string 192.168.110.254
send_string 24
send_key -m "No gateway" ENTER
send_key -m "No IPv6" ENTER
send_string -m "Enable DHCP" y
send_string 192.168.110.10
send_string 192.168.110.200
send_string -s 7 -m "Revert to HTTP on webConfigurator" y
send_key -s 1 ENTER

log "Configure Linux_LAB"
send_string -m "Set interface IP" 2
send_string -m "Select Linux_LAB" 3
send_string 192.168.120.254
send_string 24
send_key -m "No gateway" ENTER
send_key -m "No IPv6" ENTER
send_string -m "Enable DHCP" y
send_string 192.168.120.10
send_string 192.168.120.200
send_string -s 7 -m "Revert to HTTP on webConfigurator" y
send_key -s 1 ENTER

log "Enable ansible access"
send_string -m "Enable SSH" 14
send_string -s 1 y
send_string -m "Enter Shell" 8
send_string -m "Stopping firewall" "pfctl -d"

# kill $( ps ax | awk '/[0-9] +virt-viewer --connect qemu:...system --wait gw.nieslony.lab/ { print $1; }' )

if [ ! -e "$HOME/.ansible/collections/ansible_collections/pfsensible/core" ]; then
    echo "pfSense ansible collection not installed"
    ansible-galaxy collection install pfsensible.core
else
    echo "pfSense ansible collection already installed"
fi

VM_IP=$( virsh domifaddr --domain $VM_NAME | awk '/vnet/ { gsub(/\/.*/, "", $NF); print $NF; }' )
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $VM_IP, pfsense.yml
