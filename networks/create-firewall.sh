#!/bin/bash

VM_HOSTNAME=gw
VM_DOMAIN=test.lab
VM_RAM=2048
VM_DISK_SIZE=8
PREFIX_Lab_Windows_Internal=192.168.110
PREFIX_Lab_Linux_Internal=192.168.120
IP_Lab_Windows_Internal=$PREFIX_Lab_Windows_Internal.254
IP_Lab_Linux_Internal=$PREFIX_Lab_Linux_Internal.254
DHCP_FROM=10
DHCP_TO=199

DOWNLOAD_URL="https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
INSTALL_ISO="$HOME/Downloads/$( basename -s .gz $DOWNLOAD_URL )"

shopt -s extglob

function usage {
    cat <<EOF
Usage:
    $( basename $0 ) [-t|--test] [--force|-f]

Options:
    -t --test   create test VM, append "-test" to machine name
    -f --force  force delete existing machine
EOF

    exit
}

function my_sleep {
    REMAINING_SECS=$1
    shift
    MSG="$@"
    while [ $REMAINING_SECS -gt 0 ]; do
        REMAINING_SECS=$(( $REMAINING_SECS -1 ))
        echo -en "--- $MSG $REMAINING_SECS secs \r"
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
    keys="$@"
    echo "Sending key $keys ... $MSG"
    for k in $keys ; do
        virsh send-key $VM_NAME KEY_$k > /dev/null || exit 1
    done
    if [ -n "$SLEEP" ]; then
        sleep $SLEEP
    else
        sleep 1
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
    else
        sleep 1
    fi
}

while [ -n "$1" ]; do
    case "$1" in
        --test | -t)
            VM_HOSTNAME=gw-test
            ;;
        --force | -f)
            FORCE_DELETE=yes
            ;;
        *)
            usage
            ;;
    esac
    shift
done
VM_NAME=$VM_HOSTNAME.$VM_DOMAIN

log "Try to find existing machine $VM_NAME ..."
if virsh domid --domain $VM_NAME > /dev/null 2>&1 ; then
    if [ -z "$FORCE_DELETE" ]; then
        while [ "$REALLY_DELETE" != "y" -a "$REALLY_DELETE" != "n" ]; do
            read -p "Really delete existing machine $VM_NAME? (y/n) " REALLY_DELETE
            if [ "$REALLY_DELETE" = "n" ]; then
                echo "Exiting ..."
                exit
            fi
        done
    fi

    log "Force shutdown of $VM_NAME"
    virsh destroy --domain $VM_NAME
    log "Remove $VM_NAME"
    virsh undefine --domain $VM_NAME --remove-all-storage
else
    echo "Machine $VM_NAME does not exist, nothing to delete."
fi

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
echo -n "Copy installer ISO "

trap "virsh vol-delete --pool tmp --vol $TMP_ISO" EXIT

cp -v $INSTALL_ISO $TMP_ISO

virt-install \
    --name "$VM_NAME" \
    --autostart \
    --network network=Lab_Internet,model=virtio \
    --network network=Lab_Windows_Internal,model=virtio \
    --network network=Lab_Linux_Internal,model=virtio \
    --network network=Lab_DMZ,model=virtio \
    --disk path="$VM_NAME.qcow2",device=disk,size="$VM_DISK_SIZE",bus=virtio,pool=default \
    --cdrom "$TMP_ISO" \
    --osinfo freebsd14.0 \
    --memory $VM_RAM \
    --memballoon virtio \
    --graphics keymap=de \
    --clock offset=utc \
    --channel type=unix,target.name=org.qemu.guest_agent.0,target.type=virtio \
    --channel type=spicevmc,target.name=com.redhat.spice.0,target.type=virtio \
    > /dev/null 2>&1 | grep -v GSpice-WARNING &

my_sleep 60 "Booting installer..."
send_key -m "Accept License" ENTER
send_key -m "Install pfSense" ENTER
send_key -m "Create ZFS partition" ENTER
send_key -m "Proceed with Installation" ENTER
send_key -m "Stripe - no redundancy" ENTER
send_key -m "Install on vdb0" SPACE ENTER
send_key -m "Last chance, ... , really install!" LEFT ENTER

my_sleep 30 "Installing pfSense..."
send_key -m "Reboot" ENTER

my_sleep 60 "Rebooting..."

log "Assign interfaces"
send_string -m "Dont't configure vlans" n
send_string -m "Configure WAN interface" vtnet0
send_string -m "Configure LAN interface" vtnet1
send_string -m "Configure LAN interface" vtnet2
send_string -m "Configure DMZ interface" vtnet3
send_string -m "Confirm reboot" y

my_sleep 60 "Rebooting with configured interfaces..."

log "Enable ansible access"
send_string -m "Enable SSH" 14
send_string y
send_string -m "Enter Shell" 8
send_string -m "Stopping firewall" "pfctl -d"

log "Configure with ansible"

if [ ! -e "$HOME/.ansible/collections/ansible_collections/pfsensible/core" ]; then
    echo "pfSense ansible collection not installed"
    ansible-galaxy collection install pfsensible.core
else
    echo "pfSense ansible collection already installed"
fi

VM_IP=$(
    virsh domifaddr --domain $VM_NAME |
        awk '/vnet/ { gsub(/\/.*/, "", $NF); print $NF; }'
)
ssh-keygen -R $VM_IP
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $VM_IP, pfsense.yml
