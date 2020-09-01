# generate ansible boxes provision file
require_relative "external.rb"

$logger = Log4r::Logger.new('vagrant')

def read_vbox_ipv4(vm)
  begin
    # info = vm.provider.driver.read_host_only_interfaces()[0]
    # ip = info[:ip]
    # ipv6 = info[:ipv6]
    vm.provider.driver.read_guest_ip(1)
  rescue
  end
end

# Vagrant.require_plugin 'vagrant-proxyconf'

# base configuration
Vagrant.configure('2') do |config|
  if Vagrant.has_plugin?("vagrant-proxyconf")
    config.proxy.enabled = true
  end
  config.hostmanager.enabled = true
  config.hostmanager.manage_host = true
  config.hostmanager.manage_guest = true
  config.hostmanager.ignore_private_ip = false
  config.hostmanager.include_offline = false
  config.hostmanager.ip_resolver = proc do |vm, resolving_vm|
    read_vbox_ipv4(vm)
  end
  boxes = Boxes.new()

  if ENV['VAGRANT_DOTFILE_PATH']
    boxes.log_dir = File.join(ENV['VAGRANT_DOTFILE_PATH'],'boxes')
  else
    boxes.log_dir = File.join(Dir.pwd,'.vagrant','boxes')
  end

  file_dir = File.dirname(__FILE__)
  lib_dir =
  boxes_dir = File.join(File.dirname(__FILE__),'..')
  boxes_dir = File.realpath(boxes_dir)
  current_dir = Dir.pwd

  extensions = ['yaml','yml']

  dirs = [file_dir,current_dir, File.join(ENV['HOME'], ".vagrant-boxes")]

  dirs.each do |dir|
    extensions.each do |extension|
      boxes.user_config_paths.push(File.join(dir, "vagrant-boxes", "variables.#{extension}"))
      boxes.user_config_paths.push(File.join(dir, "boxes", "variables.#{extension}"))

      boxes.definitions_paths.push(File.join(dir, "vagrant-boxes/definitions/*.#{extension}"))
      boxes.definitions_paths.push(File.join(dir, "boxes/definitions/*.#{extension}"))

      boxes.provisions_paths.push(File.join(dir, "vagrant-boxes/provisions/*.#{extension}"))
      boxes.provisions_paths.push(File.join(dir, "boxes/provisions/*.#{extension}"))

      boxes.packer_paths.push(File.join(dir, "vagrant-boxes/packer/definitions/*.#{extension}"))
      boxes.packer_paths.push(File.join(dir, "boxes/packer/definitions/*.#{extension}"))

      boxes.vms_paths.push(File.join(dir, "vagrant-boxes/vms/*.#{extension}"))
      boxes.vms_paths.push(File.join(dir, "boxes/vms/*.#{extension}"))

      boxes.nodes_paths.push(File.join(dir, "user/boxes/nodes/*.#{extension}"))
      boxes.nodes_paths.push(File.join(dir, "vagrant-boxes/nodes/*.#{extension}"))
      boxes.nodes_paths.push(File.join(dir, "boxes/nodes/*.#{extension}"))
    end
  end

  boxes.config_hook = method(:config_hook)
  boxes.load()
  boxes.apply(config)
end

def get_box_hostname_from_config(node_config)

  if node_config['hostmanager'] && node_config['hostmanager']['hostname']
    res = node_config['hostmanager']['hostname']
  else
    join_operator = '.'
    if node_config['hostmanager'] && node_config['hostmanager']['join_operator']
      join_operator = node_config['hostmanager']['join_operator']
    end
    res = [
      node_config['_key'],
      node_config['_namespace'],
      node_config['variables'] && node_config['variables']['domain'] ? node_config['variables']['domain'] : ''
    ].reject { |c| c.nil? || c.empty? }.join(join_operator)
  end
  return res
end

def get_box_hostname_aliases_from_config(node_config)
  res = []

  # if node_config['hostmanager'] && node_config['hostmanager']['skip']
  #   return ''
  # end

  join_operator = '.'
  if node_config['hostmanager'] && node_config['hostmanager']['join_operator']
    join_operator = node_config['hostmanager']['join_operator']
  end

  # default = [
  #   node_config['_key'],
  #   node_config['_namespace']
  # ].reject { |c| c.nil? || c.empty? }.join(join_operator)

  # res.push(default)

  local = [
    node_config['_key'],
    node_config['_namespace'],
    'local'
  ].reject { |c| c.nil? || c.empty? }.join(join_operator)

  res.push(local)

  # puts "#{node_config['variables']}"

  if node_config['variables']['domain']
    domain = [
      node_config['_key'],
      node_config['_namespace'],
      node_config['variables'] && node_config['variables']['domain'] ? node_config['variables']['domain'] : ''
    ].reject { |c| c.nil? || c.empty? }.join(join_operator)

    res.push(domain)
  end

  if node_config['hostmanager'] && node_config['hostmanager']['dns_aliases']
    res.push(*node_config['hostmanager']['dns_aliases'])
  end

  return res
end

def config_hook(node_config, node)
  if node_config['home'] && node_config['home']['rsync']
    home_rsync(node.vm, "jvautier")
  end
  if node_config['home'] && node_config['home']['sync']
    home_sync(node.vm, "jvautier")
  end
  node.hostmanager.aliases = get_box_hostname_aliases_from_config(node_config)
  node.vm.hostname = get_box_hostname_from_config(node_config)
  node.vm.provision :hostmanager
  if node_config['proxy']
    node.vm.provider "virtualbox" do |provider, override|
      override.proxy.http = node_config['proxy']['http']
      override.proxy.https = node_config['proxy']['https']
      override.proxy.no_proxy = node_config['proxy']['no_proxy']
    end
  end


  inventory = Hash.new

  def add_inventory_group(inventory, groupname)
    if inventory[groupname]
      group = inventory[groupname]
    else
      group = Hash.new
      group['hosts'] = Hash.new
      inventory[groupname] = group
    end
    return group
  end

  def add_inventory_host(group, node_config)
    aliases = get_box_hostname_aliases_from_config(node_config)
    hostname = aliases[0]
    variables = Hash.new
    variables['ansible_user'] = 'vagrant'
    variables['ansible_ssh_pass'] = 'vagrant'
    variables['ansible_ssh_private_key_file'] = File.join("/workspaces",".vagrant", "machines", "#{node_config['_key']}.#{node_config['_namespace']}","virtualbox","private_key")
    group['hosts'][hostname] = variables
  end

  boxes.nodes.each do |index, node_config|
    # pp "#{index},#{node_config['_key']}"
    group_namespace = add_inventory_group(inventory, node_config['_namespace'])
    add_inventory_host(group_namespace,node_config)

    if node_config['ansible'] && node_config['ansible']['groups']
      groups = node_config['ansible']['groups']
      groups.each do |groupname|
        new_group = add_inventory_group(inventory, groupname)
        add_inventory_host(new_group,node_config)
      end
    end

  end
  File.write(File.join("F:","gitlab.com", "jvautier", "dev", "provisioners", "ansible", ".inventories", "boxes.yml"), inventory.to_yaml)

end