require 'yaml'

ENV['VAGRANT_NO_PARALLEL'] = 'yes'
current_dir = File.dirname(File.expand_path(__FILE__))
global_config = YAML.load_file("#{current_dir}/config.yml")

wifi_nix_usb_bus = "invalid"
wifi_nix_usb_dev = "invalid"
Dir.glob("/sys/bus/usb/devices/*").each do |dir|
        if File.exist?(dir + "/product") and File.read(dir + "/product").start_with?("802.11")
                File.readlines(dir + "/uevent").each do |line|
                        value = line.split("=")[1].strip.gsub(/^0*/, "")
                        case line.split("=")[0]
                        when "BUSNUM"
                                wifi_nix_usb_bus = value
                        when "DEVNUM"
                                wifi_nix_usb_dev = value
                        end
                end
        end
end

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
    config.proxy.no_proxy = "localhost,127.0.0.1,ipa01.linux.lab"
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

    def prepare_alma(cfg)
        cfg.vm.box = "almalinux/9"

        cfg.vm.provider :libvirt do |libvirt|
            libvirt.storage :file, :size => '16G'
        end

        cfg.vm.provision "shell",
                name: "Setup LVM and swap",
                inline: <<-'SHELL'
                dnf install -y lvm2
                DEVS=""
                for i in {b..z} ; do
                    DEV=/dev/vd$i
                    if [ -e "$DEV" ]; then
                        echo "--- Create PV on $DEV ---"
                        parted $DEV -s unit mib \
                                mklabel gpt \
                                mkpart primary 1 100% \
                                set 1 lvm on || exit 1
                        pvcreate ${DEV}1 || exit 1
                        DEVS="$DEVS ${DEV}1"
                    fi
                done

                echo "--- Create volume group ---"
                vgcreate system $DEVS || exit 1

                echo "--- Create and activate swap ---"
                lvcreate --size 4G --name swap system || exit 1
                mkswap /dev/system/swap || exit 1
                echo "/dev/system/swap swap swap defaults 0 0" >> /etc/fstab
                swapon --all --verbose || exit 1
                SHELL

        cfg.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        cfg.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"
    end

    def provision_ipa_member(cfg)
        cfg.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        cfg.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        cfg.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        cfg.vm.provision "Join IPA Domain",
                :type => "ansible" ,
                :playbook => "ansible/join-ipa-domain.yml",
                :config_file => "ansible/ansible.cfg"
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
        ipa01.vm.hostname = "ipa01.linux.lab"

        ipa01.vm.network :private_network,
                :dev => "virbr3",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route",
                :ip => "192.168.120.20",
                :netmask => "255.255.255.0",
                :hostname => true

        prepare_alma(ipa01)

        ipa01.vm.provision "shell",
                name: "Enable IPv6 for lo",
                inline: <<-'SHELL'
                sysctl -w net.ipv6.conf.lo.disable_ipv6=0
                echo "net.ipv6.conf.lo.disable_ipv6 = 0" > /etc/sysctl.d/10-ipv6.conf
                SHELL

        ipa01.vm.provision "shell",
                name: "Add default route",
                run: "always",
                inline: "route add default gw 192.168.120.254"

        ipa01.vm.provision "shell",
                name: "Set locale",
                inline: <<-'SHELL'
                if !  rpm -qa | grep -q langgg ; echo $? ; then
                        dnf install -y langpacks-en
                fi
                localectl set-locale en_US@UTF-8
                SHELL



        ipa01.vm.provision "Setup IPA",
                type: "ansible",
                playbook: "ansible/ipa01.yml",
                config_file: "ansible/ansible.cfg",
                extra_vars: {
                        maildomain: global_config["global_domain"]
                        }
    end # ipa01

    config.vm.define "mail" do |mail|
        mail.vm.hostname = "mail.linux.lab"

        mail.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
            libvirt.cpus = 2
            libvirt.storage :file, :size => '50G'
        end

        prepare_alma(mail)
        provision_ipa_member(mail)

        mail.vm.provision "Mailserver Roles",
                :type => "ansible",
                :playbook => "ansible/mail-roles.yml",
                :config_file => "ansible/ansible.cfg",
                :extra_vars => {
                        maildomain: global_config["global_domain"],
                        ipaadmin_password: global_config["ipa"]["admin_password"]
                        }
    end # mail

    config.vm.define "fedora39-01" do |fedora3901|
        fedora3901.vm.box = "generic/fedora39"
        fedora3901.vm.hostname = "fedora39-01.linux.lab"

        fedora3901.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
        end

        fedora3901.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        fedora3901.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        fedora3901.vm.provision "Workstation Basic",
                type: "ansible",
                playbook: "ansible/fedora-ws.yml",
                config_file: "ansible/ansible.cfg"

        fedora3901.vm.provision "Join IPA domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        fedora3901.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/ws_roles.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora39-01

    config.vm.define "fedora40-01" do |fedora4001|
        fedora4001.vm.box = "cloud-image/fedora-40"
        fedora4001.vm.hostname = "fedora40-01.linux.lab"

        fedora4001.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
            libvirt.machine_virtual_size = 40
        end

        fedora4001.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        fedora4001.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        fedora4001.vm.provision "Workstation Basic",
                type: "ansible",
                playbook: "ansible/fedora-ws.yml",
                config_file: "ansible/ansible.cfg"

        fedora4001.vm.provision "Join IPA domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        fedora4001.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/ws_roles.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora40-01

    config.vm.define "fedora38-01" do |fedora3801|
        fedora3801.vm.box = "generic/fedora38"
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

    config.vm.define "fileserver" do |fileserver|
        fileserver.vm.hostname = "fileserver.linux.lab"

        fileserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        prepare_alma(fileserver)
        provision_ipa_member(fileserver)

        fileserver.vm.provision "ansible",
                playbook: "ansible/fileserver.yml",
                config_file: "ansible/ansible.cfg"
    end # fileserver

    config.vm.define "webserver" do |webserver|
        webserver.vm.hostname = "webserver.linux.lab"

        webserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        prepare_alma(webserver)
        provision_ipa_member(webserver)

        webserver.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/webserver-roles.yml",
                config_file: "ansible/ansible.cfg",
                extra_vars: {
                        ipaadmin_password: global_config["ipa"]["admin_password"],
                        vhosts: [ "www.test.lab", "www.linux.lab" ]
                        }
    end # webserver

    config.vm.define "printserver" do |printserver|
        printserver.vm.box = "generic/centos9s"
        printserver.vm.hostname = "printserver.linux.lab"

        printserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        prepare_alma(printserver)
        provision_ipa_member(printserver)

        printserver.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/printserver-roles.yml",
                config_file: "ansible/ansible.cfg"
    end # printserver

    config.vm.define "accesspoint" do |accesspoint|
        accesspoint.vm.box = "generic/centos9s"
        accesspoint.vm.hostname = "accesspoint.linux.lab"

        accesspoint.vm.provider :libvirt do |libvirt|
                libvirt.usb :bus => wifi_nix_usb_bus, :device => wifi_nix_usb_dev
        end

        accesspoint.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        accesspoint.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        accesspoint.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        accesspoint.vm.provision "Join Domain",
                type: "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        accesspoint.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/hostapd-roles.yml",
                config_file: "ansible/ansible.cfg"
    end # accesspoint

    config.vm.define "gerbera" do |gerbera|
        gerbera.vm.box = "generic/centos9s"
        gerbera.vm.hostname = "gerbera.linux.lab"

        gerbera.vm.provider :libvirt do |libvirt|
            libvirt.storage :file, :size => '30G'
        end

        prepare_alma(gerbera)
        provision_ipa_member(gerbera)

        gerbera.vm.provision "Apply roles",
                type: "ansible",
                playbook: "ansible/gerbera-roles.yml",
                config_file: "ansible/ansible.cfg",
                extra_vars: {
                        ipaadmin_password: global_config["ipa"]["admin_password"],
                        }
    end # gerbera

    config.vm.define "remote_host" do |remote_host|
        remote_host.vm.box = "generic/centos9s"
        remote_host.vm.hostname = "remote-host.test.lab"

        remote_host.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        remote_host.vm.network :private_network,
                :libvirt__network_name => "Lab_Internet",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        remote_host.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        remote_host.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"

        remote_host.vm.provision "shell",
                name: "Install OpenVPN",
                inline: <<-'SHELL'
                dnf -y update
                dnf install -y epel-release
                dnf -y install openvpn
                SHELL

    end # remote_host
end
