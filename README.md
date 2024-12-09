# Vagrant Test Environment

Vagrant Test Environment creates a test environment with

* Windows Domain Controlled based on Server 2020

* FreeIPA server with trust with Microsoft AD

* basic servers like webserver, fileserver, printserver, mailserver (see details below)

* current fedora versions with GUI

The setup requires ansible roles from https://github.com/nieslony/ansible-roles.git
installed at _~/Ansible/ansible-roles_. All servers require libvirt as
virtualization platform.

## Installation

1. make yourself a member of the following local groups:

    * qemu
    * libvirt

1. to connect to libvirt via systembus `export LIBVIRT_DEFAULT_URI=qemu:///system`.
   You might want to add this to _~/.bashrc_.

1. create a copy _config.yml.template_

        cp config.yml.template config.yml

   and edit _config.yml_ with your settings.

1. create virtual networks

       cd networks
       ./create-networks.sh

   The script will create the following virtual networks:

   | Network Name         | Network          | Description                     |
   |----------------------|------------------| ------------------------------- |
   | Lab_Internet         | 192.168.100.0/24 | the virtual internet, usefull for testing VPNs
   | Lab_Linux_Internal   | 192.168.110.0/24 | contains Linux hosts
   | Lab_Windows_Internal | 192.168.120.0/24 | contains Windows hosts

1. create gateway

        ./create-firewall.sh

   The script downloads the pfSense installer and starts the installation in a
   GUI window. All neccessary keystrokes are triggered by the script. The
   ansible playbook coinfigures:

     * the Windows ans Linux network

     * static routes between Windows and Linux network

     * static routes to the openVPN network

       * 192.168.130.0/24 (client VPN)

       * 192.168.131.0/24 (site VPN)

     * DNS resolver for domains windows.lan and linux.lab

   [!CAUTION]
   Don't touch the installation! Keyboard events will disturb the indstallation
   process!

1. create Windows box

        cd Windows-Server-Core
        ./make-win2022-template.sh

   The script downloads Windows Server 2022 and installs it with all requirted
   drivers. Then it syspreps the installation and creates a Vagrant box.

1. create Windows DC

        vagrant up dc01

1. create FreeIPA server

        varant up ipa01

   Sometimes the installation of ipa01 fails because it can't find the Windows
   DC since Windows adds the management interfaces's IP address to Windows DNS
   server. A workaround is a parallel installation of dc01 and ipa01.

   After the installation you will have a trust between dc01 and ipa01.

1. create the other machines. `vagrant status` lists all available machines.
   You can run as many machines in parallel as you want depending on your
   computers's amount of RAM. A running windows DC is not required.

## Available users

| Domain      | Username   | Display Name   | Password
| ----------- | ---------- | -------------- | -----------
| LINUX.LAB   | doe        | John Doe       | UserPassword.1
| LINUX.LAB   | rossi      | Mario Rossi    | UserPassword.1
| LINUX.LAB   | mustermann | Max Mustermann | UserPassword.1
| WINDOWS.LAB | user1      | User 1         | Us.erPassword.1
| WINDOWS.LAB | user2      | User 2         | Us.erPassword.2

Please change their passwords.
