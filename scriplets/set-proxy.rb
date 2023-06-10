config.vagrant.plugins.push("vagrant-proxyconf")

global_config = YAML.load_file("#{File.dirname(__FILE__)}/../config.yml")

config.proxy.http = global_config["proxy_url"]
config.proxy.https = global_config["proxy_url"]
config.proxy.no_proxy = ".linux.lab"
