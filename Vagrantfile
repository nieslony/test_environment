require 'yaml'

ENV['VAGRANT_NO_PARALLEL'] = 'yes'
current_dir = File.dirname(File.expand_path(__FILE__))
global_config = YAML.load_file("#{current_dir}/config.yml")

Vagrant.configure("2") do |config|
    config.vagrant.plugins = [
            "vagrant-libvirt",
            "vagrant-proxyconf",
            "vagrant-timezone",
            "winrm",
            "winrm-elevated"
    ]

    config.proxy.http = global_config["proxy_url"]
    config.proxy.https = global_config["proxy_url"]
    config.proxy.no_proxy = "localhost,127.0.0.1,.lab"
    config.timezone.value = :host

    config.vm.provider :libvirt do |libvirt|
        libvirt.cpus = 2
        libvirt.memory = 2048
        libvirt.clock_offset = 'utc'
        libvirt.graphics_type = 'spice'
        libvirt.graphics_ip = "0.0.0.0"
        libvirt.graphics_port = -1
        libvirt.keymap = "de"
        libvirt.channel :type => 'unix',
            :target_name => 'org.qemu.guest_agent.0',
            :target_type => 'virtio'
        libvirt.channel :type => 'spicevmc',
            :target_name => 'com.redhat.spice.0',
            :target_type => 'virtio'
        libvirt.video_type = "qxl"
        libvirt.input :type => "mouse",
            :bus => "usb"
    end

    config.vm.define "dc01" do |dc01|
        dc01.vm.box = "win2022"
        dc01.vm.guest = "windows"
        dc01.vm.hostname = "dc01"
        dc01.vm.communicator = "winrm"

        dc01.vm.provider :libvirt do |libvirt|
                libvirt.clock_offset = 'localtime'
        end

        dc01.vm.network :private_network,
                :network_name => "Lab_Windows_Internal",
                :ip => "192.168.110.20",
                :netmask => "255.255.255.0",
                :hostname => true,
                :auto_config => false

        dc01.vm.provision "shell",
                :name => "Deploy Domain Controller",
                :path => "PowerShell/deploy-dc.ps1",
                :privileged => true,
                :args => [ "-adminpassword", global_config["dc"]["admin_password"] ],
                :reboot => true

        dc01.vm.provision "shell",
                :name => "Configure Active Directory",
                :path => "PowerShell/configure-ad.ps1",
                :privileged => true,
                :reboot => true

        dc01.vm.provision "shell",
                :name => "Configure network",
                :path => "PowerShell/network.ps1",
                :privileged => true,
                :run => "always"
    end # dc01

    config.vm.define "ipa01" do |ipa01|
        ipa01.vm.box = "generic/centos9s"
        ipa01.vm.hostname = "ipa01.linux.lab"

        ipa01.vm.network :private_network,
                :dev => "virbr3",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route",
                :ip => "192.168.120.20",
                :netmask => "255.255.255.0",
                :hostname => true

        ipa01.vm.provision "Disable IPv6",
                type: "shell",
                reboot: true,
                inline: <<-'SHELL'
                sed -i 's/net.ipv6.conf.all.disable_ipv6\s*=.*//' /etc/sysctl.conf
                SHELL

        ipa01.vm.provision "shell",
                name: "Install net-tools",
                inline: "dnf install -y net-tools"

        ipa01.vm.provision "shell",
                name: "Add default route",
                run: "always",
                inline: "route add default gw 192.168.120.254"

        ipa01.vm.provision "shell",
                name: "Set locale",
                inline: "localectl set-locale en_US@UTF-8"

        ipa01.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        ipa01.vm.provision "Setup IPA",
                type: "ansible",
                playbook: "ansible/ipa01.yml",
                config_file: "ansible/ansible.cfg",
                extra_vars: {
                        maildomain: global_config["global_domain"]
                        }
    end # ipa01

    config.vm.define "mail" do |mail|
        mail.vm.box = "generic/centos9s"
        mail.vm.hostname = "mail.linux.lab"

        mail.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
            libvirt.cpus = 2
        end

        mail.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        mail.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        mail.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        mail.vm.provision "Join IPA Domain",
                :type => "ansible" ,
                :playbook => "ansible/join-ipa-domain.yml",
                :config_file => "ansible/ansible.cfg"

        mail.vm.provision "Mailserver Roles",
                :type => "ansible",
                :playbook => "ansible/mail-roles.yml",
                :config_file => "ansible/ansible.cfg",
                :extra_vars => {
                        maildomain: global_config["global_domain"],
                        ipaadmin_password: global_config["ipa"]["admin_password"]
                        }
    end # mail

    config.vm.define "fedora38-01" do |fedora3801|
        fedora3801.vm.box = "fedora/38-cloud-base"
        fedora3801.vm.hostname = "fedora38-01.linux.lab"

        fedora3801.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
        end

        fedora3801.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        fedora3801.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        fedora3801.vm.provision "Workstation Basic",
                type: "ansible",
                playbook: "ansible/fedora-ws.yml",
                config_file: "ansible/ansible.cfg"

        fedora3801.vm.provision "Join IPA domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        fedora3801.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/ws_roles.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora38-01

    config.vm.define "fedora37-01" do |fedora3701|
        fedora3701.vm.box = "generic/fedora37"
        fedora3701.vm.hostname = "fedora37-01.linux.lab"

        fedora3701.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
        end

        fedora3701.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        fedora3701.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        fedora3701.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        fedora3701.vm.provision "Workstation Basic",
                type: "ansible",
                playbook: "ansible/fedora-ws.yml",
                config_file: "ansible/ansible.cfg"

        fedora3701.vm.provision "Join IPA domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        fedora3701.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/ws_roles.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora37-01

    config.vm.define "fileserver" do |fileserver|
        fileserver.vm.box = "generic/centos9s"
        fileserver.vm.hostname = "fileserver.linux.lab"

        fileserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        fileserver.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        fileserver.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        fileserver.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        fileserver.vm.provision "Join Domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        fileserver.vm.provision "ansible",
                playbook: "ansible/fileserver.yml",
                config_file: "ansible/ansible.cfg"
    end # fileserver

    config.vm.define "webserver" do |webserver|
        webserver.vm.box = "generic/centos9s"
        webserver.vm.hostname = "webserver.linux.lab"

        webserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        webserver.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        webserver.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        webserver.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        webserver.vm.provision "Join Domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        webserver.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/webserver-roles.yml",
                config_file: "ansible/ansible.cfg"
    end # webserver

    config.vm.define "printserver" do |printserver|
        printserver.vm.box = "generic/centos9s"
        printserver.vm.hostname = "printserver.linux.lab"

        printserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        printserver.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        printserver.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        printserver.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        printserver.vm.provision "Join Domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        printserver.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/printserver-roles.yml",
                config_file: "ansible/ansible.cfg"
    end # printserver
end
