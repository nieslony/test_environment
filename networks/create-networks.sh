#!/bin/bash

for i in Lab*xml ; do
    NET_NAME="$( xpath -q -e 'network/name/text()' $i )"

    echo "--- Reading network '$NET_NAME' from '$i' ---"
    virsh net-define $i
    virsh net-autostart $NET_NAME
    virsh net-start $NET_NAME
done
