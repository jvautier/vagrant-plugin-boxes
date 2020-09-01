# -*- mode: ruby -*-
# vi: set ft=ruby :
require 'pathname'
require 'ipaddr'
require 'yaml'
require 'json'
require 'socket'
require 'open3'
require 'erb'
require 'pp'
require_relative 'vagrant-boxes-provisioners'
# add colors to string
class String
  def black;          "\e[30m#{self}\e[0m" end
  def red;            "\e[31m#{self}\e[0m" end
  def green;          "\e[32m#{self}\e[0m" end
  def brown;          "\e[33m#{self}\e[0m" end
  def blue;           "\e[34m#{self}\e[0m" end
  def magenta;        "\e[35m#{self}\e[0m" end
  def cyan;           "\e[36m#{self}\e[0m" end
  def gray;           "\e[37m#{self}\e[0m" end
  
  def bg_black;       "\e[40m#{self}\e[0m" end
  def bg_red;         "\e[41m#{self}\e[0m" end
  def bg_green;       "\e[42m#{self}\e[0m" end
  def bg_brown;       "\e[43m#{self}\e[0m" end
  def bg_blue;        "\e[44m#{self}\e[0m" end
  def bg_magenta;     "\e[45m#{self}\e[0m" end
  def bg_cyan;        "\e[46m#{self}\e[0m" end
  def bg_gray;        "\e[47m#{self}\e[0m" end
  
  def bold;           "\e[1m#{self}\e[22m" end
  def italic;         "\e[3m#{self}\e[23m" end
  def underline;      "\e[4m#{self}\e[24m" end
  def blink;          "\e[5m#{self}\e[25m" end
  def reverse_color;  "\e[7m#{self}\e[27m" end
end
# variables for minimal version check
vbox_min_version = '5.2.10'
vagrant_min_version = '2.0.0'
vagrant_recommended_min_version = '2.1.1'



# Vagrant.require_version '>= ' + vagrant_min_version
vboxversion = `vboxmanage --version`
if Vagrant::VERSION < vagrant_recommended_min_version
  warn "Vagrant minimal recommended version is #{vagrant_recommended_min_version}.".red
end
# check virtualbox version
if vboxversion < vbox_min_version
  warn "VirtualBox recommended version is #{vbox_min_version}.".red
end
# check if vagrant-proxyconf is installed
unless Vagrant.has_plugin?('vagrant-proxyconf')
  warn "Vagrant plugin is missing: vagrant-proxyconf. Please install with `vagrant plugin install vagrant-proxyconf --plugin-version 1.5.2`".red
end
# check if vagrant-hostmanager is installed
unless Vagrant.has_plugin?('vagrant-hostmanager')
  warn "Vagrant plugin is missing: vagrant-proxyconf. Please install with `vagrant plugin install vagrant-hostmanager --plugin-version 1.8.8`".red
end

$vagrant_root_dir = Pathname.new(File.join(File.dirname(__FILE__),'..')).cleanpath
$boxes_logs_dir = Pathname.new(File.join($vagrant_root_dir, '.vagrant','boxes')).cleanpath
FileUtils.remove_dir($boxes_logs_dir,true) 

$boxes_config = {}

$user = {}
# vms hash
$vms = {}
# definitions hash
$definitions = {}
$provisions = {}
# logger used for hostmanager ip resolving
$logger = Log4r::Logger.new('vagrant')
# add deep_merge function on Hash class
class ::Hash
  def deep_merge(second)
      merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
      self.merge(second, &merger)
  end
  def sort_by_key(recursive = false, &block)
    self.keys.sort(&block).reduce({}) do |seed, key|
      seed[key] = self[key]
      if recursive && seed[key].is_a?(Hash)
        seed[key] = seed[key].sort_by_key(true, &block)
      end
      seed
    end
  end
end
# clone object helper
def object_clone(target)
  clone = Marshal.load( Marshal.dump(target))
  return clone
end
# log file creation helper
def log_to_file(filepath, object)
  #puts "log_to_file #{filepath}"
  final_path = File.join($boxes_logs_dir, filepath)
  pn = Pathname.new(final_path).cleanpath
  FileUtils.mkdir_p(pn.dirname)
  File.write(File.join(final_path), object)
end

# load yaml helper (includes ERB interpolation)
def load_yaml(yaml_path, variables = nil)
  #puts "load_yaml #{yaml_path}"
  if variables
    YAML.load(ERB.new(File.read(yaml_path)).result(OpenStruct.new(variables).instance_eval { binding }))  
  else
    YAML.load(ERB.new(File.read(yaml_path)).result)
  end
end
# load definitions from a directory path
def load_user(filepath)
  $user = load_yaml(filepath)
end
# load definitions from a directory path
def load_definitions(dirpath)
  Dir.glob(dirpath) do |item|
    namespace = File.basename(item, ".*")
    definitions = load_yaml(item)
    definitions.each do |key, value|
      definition_key = "#{key}.#{namespace}"
      if $definitions[definition_key]
        $definitions[definition_key] = $definitions[definition_key].deep_merge(value)
      else
        $definitions[definition_key] = value
      end
    end
  end
  log_to_file("_definitions.yaml",  $definitions.sort_by_key(true).to_h.to_yaml)
end
# load definitions from a directory path
def load_provisions(dirpath)
  Dir.glob(dirpath) do |item|
    namespace = File.basename(item, ".*")
    provisions = load_yaml(item)
    provisions.each do |key, value|
      provision_key = "#{key}.#{namespace}"
      if $provisions[provision_key]
        $provisions[provision_key] = $provisions[provision_key].deep_merge(value)
      else
        $provisions[provision_key] = value
      end
    end
  end
  log_to_file("_provisions.yaml",  $provisions.sort_by_key(true).to_h.to_yaml)
end
# load vms from a directory path
def load_vms_dir(dirpath, vagrant_config)
  Dir.glob(dirpath) do |filepath|
    namespace = File.basename(filepath, ".*") # stackfilename
    vms_file = load_yaml(filepath)
    vms_file.each do |key, value|      
      vm_config = value
      vm_config['lib'] = vm_config['lib'] || {}
      vm_config['lib']['namespace'] = namespace
      vm_config['lib']['key'] = "#{key}"
      vm_hash_id = "#{vm_config['lib']['key']}.#{vm_config['lib']['namespace']}"
      # puts "resolving #{vm_hash_id}"
      unless value['definition'].to_s.empty?
        if $definitions[value['definition']]
          # puts "#{vm_hash_id} has #{value['definition']}"
          definition = $definitions[value['definition']]
          vm_config = definition.deep_merge(vm_config)
        end
      end
      if $vms[vm_hash_id]
        # puts "merging #{vm_hash_id}"
        vm_config = $vms[vm_hash_id].deep_merge(vm_config)
      else
        # puts "not merging #{vm_hash_id}"
      end
      if $user
        vm_config = $user.deep_merge(vm_config)
      end
      $vms[vm_hash_id] = vm_config
    end
  end
end
def set_instance_variable(src, dest, field, default = nil )
  prop_name = "@#{field}".to_sym # you need the property name, prefixed with a '@', as a symbol
  if src[field]
    dest.instance_variable_set(prop_name, src[field])
  elsif default
    dest.instance_variable_set(prop_name, default)
  end
end
def set_object_property(src, dest, field, default = nil)
  if src[field]
    dest.send("#{field}=", src[field])
  else
    if default 
      dest.send("#{field}=", default)
    end
  end
end
def set_hash_property(src, dest, field, default = nil)
  if src[field]
    dest[field] = src[field]
  else
    if default 
      dest[field] = default
    end
  end
end
# configure a box
def configure_node(node_config, box)
  $config_hook.call(node_config, box)
  vm = box.vm
  vm_config = node_config['vm']
  
  set_instance_variable(vm_config, vm, 'box_url')
  set_instance_variable(vm_config, vm, 'box_download_insecure')
  set_instance_variable(vm_config, vm, 'box')
  set_instance_variable(vm_config, vm, 'box_check_update', true)

  synced_folder = vm_config['synced_folder'] || {}
  synced_folder.each do |synced_folder_key, synced_folder_config|
    target_config = {}
    set_hash_property(synced_folder_config, target_config, 'src')
    set_hash_property(synced_folder_config, target_config, 'dest')
    set_hash_property(synced_folder_config, target_config, 'create', false)
    set_hash_property(synced_folder_config, target_config, 'disabled', false)
    set_hash_property(synced_folder_config, target_config, 'group', "")
    set_hash_property(synced_folder_config, target_config, 'mount_options', [])
    set_hash_property(synced_folder_config, target_config, 'owner', "")
    set_hash_property(synced_folder_config, target_config, 'type', "")
    set_hash_property(synced_folder_config, target_config, 'id', synced_folder_key)
    vm.synced_folder target_config['src'], target_config['dest'], create: target_config['create'], disabled: target_config['disabled'], group: target_config['group'], mount_options: target_config['mount_options'], owner: target_config['owner'], type: target_config['type'], id: target_config['id']
  end
  network = vm_config['network'] || {}
  network.each do |network_config_key, network_config|
      case network_config_key
      when 'forwarded_port'
        network_config.each do |forwarded_port_config|
          vm.network "forwarded_port", guest: forwarded_port_config['guest'], host: forwarded_port_config['host']
        end
      when 'private_network'
        private_network_config = {}
        set_hash_property(network_config, private_network_config, 'ip',  nil)
        set_hash_property(network_config, private_network_config, 'type',  nil)
        vm.network "private_network", ip: private_network_config['ip'], type: private_network_config['type']
      when 'public_network'
        public_network_config = {}
        set_hash_property(network_config, public_network_config, 'ip',  nil)
        set_hash_property(network_config, public_network_config, 'use_dhcp_assigned_default_route',  nil)
        set_hash_property(network_config, public_network_config, 'bridge', nil)
        set_hash_property(network_config, public_network_config, 'auto_config',  nil)
        vm.network "public_network", ip: public_network_config['ip'], bridge: public_network_config['bridge'], use_dhcp_assigned_default_route: target_config['use_dhcp_assigned_default_route']
      else
        warn "#{network_config_key} is not a valid network identifier".red
      end
  end
  
  virtual_box_config = vm_config['provider']['virtualbox']
  vm.provider "virtualbox" do |virtualbox|
    set_object_property(virtual_box_config, virtualbox, 'name', "#{node_config['lib']['key']}.#{node_config['lib']['namespace']}" )
    set_object_property(virtual_box_config, virtualbox, 'memory' )
    set_object_property(virtual_box_config, virtualbox, 'cpus' )
    set_object_property(virtual_box_config, virtualbox, 'gui' )
    customize_config = virtual_box_config['customize']
    customize_config.each do |customize_config_key, customize_config_value|
      virtualbox.customize ["modifyvm", :id, "--#{customize_config_key}", customize_config_value]
    end
  end
  if node_config['provision']
    node_config['provision'].each do |provision_name, provision_config|

      unless provision_config['definition'].to_s.empty?
        if $provisions[provision_config['definition']]
          provision_definition = $provisions[provision_config['definition']]
          provision_config = provision_definition.deep_merge(provision_config)
          node_config['provision'][provision_name] = provision_config
          if $user['provision'] && $user['provision'][provision_name]
            provision_config = provision_config.deep_merge($user['provision'][provision_name])
            node_config['provision'][provision_name] = provision_config
          end
  
        end
      end
  
      if provision_config['type']
        case provision_config['type']
        when 'shell'
          provision_shell(box, provision_name, provision_config, node_config)
        when 'ansible_local'
          provision_ansible_local(box, provision_name, provision_config, node_config)
        when 'ansible'
          provision_ansible(box, provision_name, provision_config, node_config)
        when 'chef_zero'
          provision_chef_zero(box, provision_name, provision_config, node_config)
        when 'chef_solo'
          provision_chef_solo(box, provision_name, provision_config, node_config)
        when 'chef_client'
          provision_chef_client(box, provision_name, provision_config, node_config)
        else
          warn "#{value['type']} is not a valid provision type".red
        end
      end
    end
  end

end

# loop to configure all vms from $vms
def configure_vms(config)
  $vms.each do |key,vm_config|
    # pp vm_config
    config.vm.define key, autostart: vm_config['autostart'] || false do |node|
      # node.ssh.insert_key = true
      # node.ssh.username = "toto"
      
      configure_node(vm_config, node)
      vm_config_copy = object_clone(vm_config)
      vm_config_copy.delete('packer')
      # generate packer
      packer_gen(vm_config)
      log_to_file("vms/#{vm_config['lib']['namespace']}/#{vm_config['lib']['key']}.yaml", vm_config_copy.sort_by_key(true).to_h.to_yaml)
    end
  end
end

def packer_gen(vm_config)
  # pp vm_config
  if vm_config['packer']
    if vm_config['packer']['template']
      template_path = File.join($vagrant_root_dir,vm_config['packer']['template'])
      packer_definition = load_yaml(template_path, vm_config)
      packer_definition['provisioners'] = packer_definition['provisioners'] + vm_config['packer']['provisioners']
      vm_hash_id = "#{vm_config['lib']['key']}.#{vm_config['lib']['namespace']}"
      if vm_config['packer']['template_output_dir']
        file_path=File.join(vm_config['packer']['template_output_dir'], "#{vm_hash_id}.json")
        dir_path=File.dirname(file_path)
        FileUtils.mkdir_p(dir_path) unless File.exists?(dir_path)
        File.write(file_path, JSON.pretty_generate(packer_definition))
        File.write(File.join(file_path), JSON.pretty_generate(packer_definition))
      end
      log_to_file("packer/#{vm_config['lib']['namespace']}/#{vm_config['lib']['key']}.yaml", packer_definition.sort_by_key(true).to_h.to_yaml)
      log_to_file("packer/#{vm_config['lib']['namespace']}/#{vm_config['lib']['key']}.json", JSON.pretty_generate(packer_definition))
    end
  end
end