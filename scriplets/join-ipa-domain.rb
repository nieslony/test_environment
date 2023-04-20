dirname = File.dirname(__FILE__)

config.vm.provision "Join IPA domain",
        type: "ansible",
        playbook: "#{dirname}/../ansible/join-ipa-domain.yml",
        config_file: "#{dirname}/../ansible/ansible.cfg"
