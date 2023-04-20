dirname = File.dirname(__FILE__)

config.vm.provision "Install role webserver",
        type: "ansible",
        playbook: "#{dirname}/../ansible/webserver-roles.yml",
        config_file: "#{dirname}/../ansible/ansible.cfg"
