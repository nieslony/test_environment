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
    config.proxy.no_proxy = "localhost,127.0.0.1,192.168.0.0/16,linux.lab,.linux.lab"
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

        cfg.vm.provision "ansible",
                playbook: "ansible/create-LVM-and-swap.yml",
                config_file: "ansible/ansible.cfg"

        cfg.vm.provision "Sync with RTC on host",
                type: "ansible",
                playbook: "ansible/host-wide-timesync.yml",
                config_file: "ansible/ansible.cfg"
    end

    def setup_network(cfg, networks="Lab_Linux_Internal")
            networks.split(/ *, */, -1).each() do |nw|
                    cfg.vm.network :private_network,
                        :libvirt__network_name => nw,
                        :libvirt__forward_mode => "route"
            end

            cfg.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh",
                args: networks.split(/ *, */, -1).first()
    end

    def provision_ipa_member(cfg)
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
        setup_network(ipa01)

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
        setup_network(mail)
        provision_ipa_member(mail)

        mail.vm.provision "Apply Roles",
                :type => "ansible",
                :playbook => "ansible/roles/mail.yml",
                :config_file => "ansible/ansible.cfg",
                :extra_vars => {
                        maildomain: global_config["global_domain"],
                        ipaadmin_password: global_config["ipa"]["admin_password"]
                        }
    end # mail

    config.vm.define "fileserver" do |fileserver|
        fileserver.vm.hostname = "fileserver.linux.lab"

        fileserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        prepare_alma(fileserver)
        setup_network(fileserver)
        provision_ipa_member(fileserver)

        fileserver.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/fileserver.yml",
                config_file: "ansible/ansible.cfg"
    end # fileserver

    config.vm.define "webserver" do |webserver|
        webserver.vm.hostname = "webserver.linux.lab"

        webserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        prepare_alma(webserver)
        setup_network(webserver)
        provision_ipa_member(webserver)

        webserver.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/webserver.yml",
                config_file: "ansible/ansible.cfg",
                extra_vars: {
                        ipaadmin_password: global_config["ipa"]["admin_password"]
                        }
    end # webserver

    config.vm.define "printserver" do |printserver|
        printserver.vm.hostname = "printserver.linux.lab"

        printserver.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        prepare_alma(printserver)
        setup_network(printserver)
        provision_ipa_member(printserver)

        printserver.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/printserver.yml",
                config_file: "ansible/ansible.cfg"
    end # printserver

    config.vm.define "accesspoint" do |accesspoint|
        accesspoint.vm.hostname = "accesspoint.linux.lab"

        accesspoint.vm.provider :libvirt do |libvirt|
                libvirt.usb :bus => wifi_nix_usb_bus, :device => wifi_nix_usb_dev
        end

        prepare_alma(accesspoint)
        setup_network(accesspoint)
        provision_ipa_member(accesspoint)

        accesspoint.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/hostapd.yml",
                config_file: "ansible/ansible.cfg"
    end # accesspoint

    config.vm.define "gerbera" do |gerbera|
        gerbera.vm.hostname = "gerbera.linux.lab"

        gerbera.vm.provider :libvirt do |libvirt|
            libvirt.storage :file, :size => '30G'
        end

        prepare_alma(gerbera)
        setup_network(gerbera)
        provision_ipa_member(gerbera)

        gerbera.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/gerbera.yml",
                config_file: "ansible/ansible.cfg",
                extra_vars: {
                        ipaadmin_password: global_config["ipa"]["admin_password"],
                        }
    end # gerbera

    config.vm.define "remote_host" do |remote_host|
        remote_host.vm.hostname = "remote-host.test.lab"

        remote_host.vm.provider :libvirt do |libvirt|
            libvirt.memory = 1024
        end

        prepare_alma(remote_host)
        setup_network(remote_host, networks="Lab_Internet")

        remote_host.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/remote_host.yml",
                config_file: "ansible/ansible.cfg"
    end # remote_host

    config.vm.define "fedora39-01" do |fedora3901|
        fedora3901.vm.box = "generic/fedora39"
        fedora3901.vm.hostname = "fedora39-01.linux.lab"

        fedora3901.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
        end

        setup_network(fedora3901, networks="Lab_Linux_Internal,Lab_Internet")
        provision_ipa_member(fedora3901)

        fedora3901.vm.provision "Workstation Basic",
                type: "ansible",
                playbook: "ansible/fedora-ws.yml",
                config_file: "ansible/ansible.cfg"

        fedora3901.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/workstation.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora39-01

    config.vm.define "fedora40-01" do |fedora4001|
        fedora4001.vm.box = "fedora/40-cloud-base"
        fedora4001.vm.hostname = "fedora40-01.linux.lab"

        fedora4001.vm.provider :libvirt do |libvirt|
            libvirt.memory = 4096
            libvirt.machine_virtual_size = 40
        end

        fedora4001.vm.provision "Resize /",
                type: "shell",
                inline: <<-SHELL
                growpart /dev/vda 4
                btrfs filesystem resize max /
                SHELL

        setup_network(fedora4001, networks="Lab_Linux_Internal,Lab_Internet")
        provision_ipa_member(fedora4001)

        fedora4001.vm.provision "Workstation Basic",
                type: "ansible",
                playbook: "ansible/fedora-ws.yml",
                config_file: "ansible/ansible.cfg"

        fedora4001.vm.provision "Apply Roles",
                type: "ansible",
                playbook: "ansible/roles/workstation.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora40-01
end
