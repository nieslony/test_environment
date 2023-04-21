dirname = File.dirname(__FILE__)

config.vm.hostname = "#{hostname}.linux.lab"

config.vm.network :private_network,
        :libvirt__network_name => "Lab_Linux_Internal",
        :libvirt__autostart => "true",
        :libvirt__forward_mode => "route"

config.vm.provision "shell",
        name: "Setup network",
        path: "#{dirname}/../ansible/network.sh"