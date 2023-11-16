#!/bin/bash

MANAGEMENT_NET=192.168.121.0
MANAGEMENT_GW=192.168.121.1

echo "Install package"
if rpm -qa | grep net-tools -q ; then
        echo "net-tools already installed"
else
        echo Installing net-tools
        dnf install -y net-tools
fi

echo "Removing default gateway $MANAGEMENT_GW"
route del default gw $MANAGEMENT_GW

echo "Renaming networks"
for uuid in $( nmcli --field UUID con show | grep -v UUID ) ; do
        ip=$( nmcli con show $uuid | awk '/IP4.ADDRESS/ { print $NF; }' )
        new_nw_name=""
        case $ip in
                192.168.121.*)
                        new_nw_name="Management"
                        echo "Ignore DNS for network $uuid"
                        nmcli con modify $uuid ipv4.ignore-auto-dns yes ipv4.ignore-auto-routes yes
                        ;;
                192.168.100.*)
                        new_nw_name="Internet"
                        ;;
                192.168.110.*)
                        new_nw_name="Lab_Windows_Internal"
                        ;;
                192.168.120.*)
                        new_nw_name="Lab_Linux_Internal"
                        ;;
        esac

        if [ -n "$new_nw_name" ]; then
                echo "Renaming network $uuid -> $new_nw_name"
                nmcli connection modify $uuid con-name "$new_nw_name"
        fi
done

echo "Remove IPv6 entries from /etc/hosts"
sed -i '/^.*::.*$/d' /etc/hosts

echo "Remove management IP from /etc/resolv.conf"
if grep -q "192.168.120.*" /etc/resolv.conf ; then
        sed -i 's/.*192.168.121.*//' /etc/resolv.conf
fi

echo "Removing entries like 127.0.0.1 $HOSTNAME from /etc/hosts"
sed -i "/127.0.[0-9]*.1.*$HOSTNAME.*/d" /etc/hosts

echo Copy proxy config from yum.conf to dnf.conf
grep proxy /etc/yum.conf >> /etc/dnf/dnf.conf
