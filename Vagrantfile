require 'yaml'

current_dir = File.dirname(File.expand_path(__FILE__))
global_config = YAML.load_file("#{current_dir}/config.yml")

Vagrant.configure("2") do |config|
    config.vagrant.plugins = [ "vagrant-libvirt", "vagrant-proxyconf", "vagrant-timezone", "winrm", "winrm-elevated" ]

    config.proxy.http = global_config["proxy_url"]
    config.proxy.https = global_config["proxy_url"]
    config.timezone.value = :host

    config.vm.define "dc01" do |dc01|
        dc01.vm.box = "win2022"
        dc01.vm.guest = "windows"
        dc01.vm.hostname = "dc01"
        dc01.vm.communicator = "winrm"

        dc01.vm.provider :libvirt do |libvirt|
            libvirt.cpus = 2
            libvirt.memory = 2048
            libvirt.clock_offset = 'localtime'
            libvirt.graphics_type = 'spice'
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
        ipa01.vm.box = "centos/stream8"
        ipa01.vm.hostname = "ipa01.linux.lab"

        ipa01.vm.provider :libvirt do |libvirt|
            libvirt.cpus = 2
            libvirt.memory = 2048
            libvirt.keymap = "de"
        end

#                :libvirt__network_name => "Lab_Linux_Internal",
        ipa01.vm.network :private_network,
                :dev => "virbr3",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route",
                :ip => "192.168.120.20",
                :netmask => "255.255.255.0",
                :hostname => true

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

        ipa01.vm.provision "ansible",
                playbook: "ansible/ipa01.yml",
                config_file: "ansible/ansible.cfg"
    end # ipa01

    config.vm.define "mail" do |mail|
        mail.vm.box = "centos/stream8"
        mail.vm.hostname = "mail.linux.lab"

        mail.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        mail.vm.provision "ansible" do |ansible|
            ansible.playbook = "ansible/set-proxy.yml"
            ansible.config_file = "ansible/ansible.cfg"
        end

        mail.vm.provision "ansible" do |ansible|
            ansible.playbook = "ansible/join-ipa-domain.yml"
            ansible.config_file = "ansible/ansible.cfg"
        end

        mail.vm.provision "Mailserver",
                :type => "ansible",
                :playbook => "ansible/mailserver.yml",
                :verbose => true
    end # mail

    config.vm.define "fedora35-01" do |fedora3501|
        fedora3501.vm.box = "fedora/35-cloud-base"
        fedora3501.vm.hostname = "fedora35-01.linux.lab"

        fedora3501.vm.provider :libvirt do |libvirt|
            libvirt.cpus = 2
            libvirt.memory = 4096
            libvirt.keymap = "de"
        end

        fedora3501.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        fedora3501.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        fedora3501.vm.provision "ansible",
                playbook: "ansible/fedora-ws.yml",
                verbose: true,
                config_file: "ansible/ansible.cfg"

        fedora3501.vm.provision "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora35-01

    config.vm.define "fedora36-01" do |fedora3601|
        fedora3601.vm.box = "fedora/36-cloud-base"
        fedora3601.vm.hostname = "fedora36-01.linux.lab"

        fedora3601.vm.provider :libvirt do |libvirt|
            libvirt.cpus = 2
            libvirt.memory = 4096
            libvirt.keymap = "de"
        end

        fedora3601.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        fedora3601.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        fedora3601.vm.provision "ansible",
                playbook: "ansible/fedora-ws.yml",
                verbose: true,
                config_file: "ansible/ansible.cfg"

        fedora3601.vm.provision "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"
    end # fedora36-01

    config.vm.define "webserver" do |webserver|
        webserver.vm.box = "centos/stream8"
        webserver.vm.hostname = "webserver.linux.lab"

        webserver.vm.provider :libvirt do |libvirt|
            libvirt.cpus = 2
            libvirt.memory = 1024
            libvirt.keymap = "de"
        end

        webserver.vm.network :private_network,
                :libvirt__network_name => "Lab_Linux_Internal",
                :libvirt__autostart => "true",
                :libvirt__forward_mode => "route"

        webserver.vm.provision "shell",
                name: "Setup network",
                path: "ansible/network.sh"

        webserver.vm.provision "ansible",
                playbook: "ansible/join-ipa-domain.yml",
                config_file: "ansible/ansible.cfg"

        webserver.vm.provision "ansible",
                playbook: "ansible/webserver.yml",
                config_file: "ansible/ansible.cfg"
    end # webserver
end
