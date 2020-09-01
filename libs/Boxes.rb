require 'pathname'
require 'ipaddr'
require 'yaml'
require 'json'
require 'socket'
require 'open3'
require 'erb'
require 'pp'

# $logger = Log4r::Logger.new("vagrant::ui::interface")

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

class Boxes

  attr_accessor :vagrant_config
  attr_accessor :log_dir
  attr_accessor :user_config
  attr_accessor :user_config_path
  attr_accessor :user_config_paths
  attr_accessor :definitions_paths
  attr_accessor :provisions_paths
  attr_accessor :packer_paths
  attr_accessor :vms_paths
  attr_accessor :nodes_paths
  attr_accessor :config_hook

  attr_reader :definitions
  attr_reader :provisions
  attr_reader :packers
  attr_reader :vms
  # attr_reader :nodes
  attr_reader :logger

  def initialize(master_namespace = nil)
    @logger = Log4r::Logger.new('vagrant::boxes')

    # boxes_dir = File.join(File.dirname(__FILE__),'..')
    # boxes_dir = File.realpath(boxes_dir)
    @master_namespace = master_namespace
    @user_config = {}
    @user_config_path = nil
    @user_config_paths = []
    @definitions_paths = []
    @provisions_paths = []
    @packer_paths = []
    @nodes_paths = []
    @vms_paths = []
    @definitions = {}
    @provisions = {}
    @packers = {}
    @vms={}
    @nodes={}

    @boxes_root_dir = File.realpath(File.dirname(File.join(File.dirname(__FILE__), "..", "..")))

    extensions = ['yaml','yml']
    extensions.each do |extension|
      @definitions_paths.push(File.join(@boxes_root_dir, "vagrant/boxes/definitions/*.#{extension}"))
      @provisions_paths.push(File.join(@boxes_root_dir, "vagrant/boxes/provisions/*.#{extension}"))
      @packer_paths.push(File.join(@boxes_root_dir, "packer/definitions/*.#{extension}"))
      @vms_paths.push(File.join(@boxes_root_dir, "vagrant/boxes/vms/*.#{extension}"))
      @vms_paths.push(File.join(@boxes_root_dir, "teams/**/boxes/vms/*.#{extension}"))
      @vms_paths.push(File.join(@boxes_root_dir, "user/boxes/vms/*.#{extension}"))
      @vms_paths.push(File.join(@boxes_root_dir, "trainings/**/boxes/vms/*.#{extension}"))
      @nodes_paths.push(File.join(@boxes_root_dir, "user/boxes/nodes/*.#{extension}"))
    end

  end

  def nodes
    @nodes
  end
  def object_clone(target)
    clone = Marshal.load( Marshal.dump(target))
    return clone
  end
  def log_to_file(filepath, object)
    if log_dir
      final_path = File.join(log_dir, filepath)
      pn = Pathname.new(final_path).cleanpath
      FileUtils.mkdir_p(pn.dirname)
      File.write(File.join(final_path), object)
    end
  end
  def load_yaml(yaml_path, variables = nil)
    res = {}
    begin
    if File.file?(yaml_path)
      if variables.nil?
        variables = Hash.new
      end
      variables['boxes_root_dir'] = @boxes_root_dir
      variables['yaml_dir'] = File.realpath(File.dirname(yaml_path))

      res = YAML.load(ERB.new(File.read(yaml_path)).result(OpenStruct.new(variables).instance_eval { binding }))
    end
    rescue Exception => e
      puts "Something bad happend to #{yaml_path} #{e}"
      raise e
    end
    return res
  end
  def concat_array(array)
    box_name = array.reject { |c| c.nil? || c.empty? }.join('.')
  end
  def set_instance_variable(src, dest, field, default = nil )
    prop_name = "@#{field}".to_sym
    if src && src[field]
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
    if src.has_key?(field)
      dest[field] = src[field]
    else
      if default
        dest[field] = default
      end
    end
  end
  def map(src, dest, type = "instance")
    # pp src
    unless src.nil?
      src.each do |key, value|
        if key[0] != '_'
          if type == "instance"
            set_instance_variable(src, dest, key )
          end
          if type == "object"
            set_object_property(src, dest, key )
          end
          if type == "hash"
            set_hash_property(src, dest, key )
          end
        else
          # p "field skiped #{key}"
        end

      end
    end
  end
  def add_definitions(paths)
    load_collection(paths, definitions, @master_namespace)
  end
  def add_provisions(paths)
    load_collection(paths, provisions, @master_namespace)
  end
  def add_packers(paths)
    load_collection(paths, packers, @master_namespace)
  end
  def add_vms(paths)
    load_collection(paths, vms, @master_namespace)
  end
  def add_nodes(paths)
    load_collection(paths, nodes, @master_namespace)
  end
  def load_collection(paths, collection, master_namespace = nil)

    Dir.glob(paths) do |file|
      namespace = File.basename(file, ".*")
      if master_namespace
        namespace = "#{namespace}.#{master_namespace}"
      end
      content = load_yaml(file)
      unless content.nil?
        content.each do |key, value|
          value['_key'] = key
          value['_namespace'] = namespace
          hash_key = "#{key}.#{namespace}"
          if collection[hash_key]
            collection[hash_key] = collection[hash_key].deep_merge(value)
          else
            collection[hash_key] = value
          end
        end
      end
    end
  end
  def load()

    user_config = Hash.new
    Dir.glob(user_config_paths) do |file|
      content = load_yaml(file)
      if content && !content.nil?
        user_config = user_config.deep_merge(content)
      end
    end

    load_collection(definitions_paths, definitions)
    load_collection(provisions_paths, provisions)
    load_collection(packer_paths, packers)
    load_collection(vms_paths, vms)
    load_collection(nodes_paths, nodes, @master_namespace)

    nodes.each do |node_key,node_config|

      node_config_current = object_clone(node_config)

      unless node_config_current['_definition'].to_s.empty?
        node_definition_name = node_config_current['_definition']
        if definitions[node_definition_name]
          definition = definitions[node_definition_name]
          node_config_current = definition.deep_merge(node_config_current)
        end
      end
      if node_config_current.has_key?("vm") && node_config_current['vm'].has_key?("_definition")
        node_vm_name = node_config_current['vm']['_definition']
        if vms[node_vm_name]
          vm = vms[node_vm_name]
          node_config_current['vm'] = vm.deep_merge(node_config_current['vm'])
        end
      end

      node_config_current = user_config.deep_merge(node_config_current)

      if node_config_current['provision']
        node_config_current['provision'].each do |provision_name, provision_config|
          unless provision_config['_definition'].to_s.empty?
            # if user_config.has_key?("provision") && user_config['provision'][provision_name]
            #   provision_config = provision_config.deep_merge(user_config['provision'][provision_name])
            #   node_config_current['provision'][provision_name] = provision_config
            # end
            if provisions[provision_config['_definition']]
              provision_definition = provisions[provision_config['_definition']]
              provision_config = provision_definition.deep_merge(provision_config)
              node_config_current['provision'][provision_name] = provision_config
            else
              puts "provision definition #{provision_config['_definition']} not found in #{node_key}"
            end
          end
        end
        node_config_current['provision'] = node_config_current['provision'].values.sort_by { |obj| obj['_priority'] || 0 }
      end

      nodes[node_key] = node_config_current;
      # log_to_file("nodes/#{node_config_current['_namespace']}/#{node_config_current['_key']}.yaml", node_config_current.sort_by_key(true).to_h.to_yaml)



    end

    nodes_2 = Hash.new
    nodes.each do |node_key,node_config|
      node_config_current = object_clone(node_config)
      if node_config_current['_count']
        count = node_config_current['_count']
        count.times do |index|
          indexDisplay = index + 1
          clone = object_clone(node_config_current)
          clone['_index'] = index
          newKey = "#{node_config['_key']}-#{indexDisplay}"
          # TODO? keep key override ?
          clone['_key'] = newKey
          # puts "newKey=#{newKey}"
          nodes_2["#{newKey}.#{clone['_namespace']}"] = clone;
          log_to_file("nodes/#{node_config_current['_namespace']}/#{newKey}.yaml", clone.sort_by_key(true).to_h.to_yaml)
        end
      else
        nodes_2[node_key] = node_config_current;
        log_to_file("nodes/#{node_config_current['_namespace']}/#{node_config_current['_key']}.yaml", node_config_current.sort_by_key(true).to_h.to_yaml)
      end
    end

    @nodes = nodes_2

    log_to_file("definitions.yaml",  definitions.sort_by_key(true).to_h.to_yaml)
    log_to_file("provision.yaml",  provisions.sort_by_key(true).to_h.to_yaml)
    log_to_file("packers.yaml",  packers.sort_by_key(true).to_h.to_yaml)
    log_to_file("vms.yaml",  vms.sort_by_key(true).to_h.to_yaml)
    log_to_file("nodes.yaml",  @nodes.sort_by_key(true).to_h.to_yaml)

  end
  def apply(vagrant_config)
    @nodes.each do |node_key,node_config|
      # puts "apply #{node_key}"
      configure_node(vagrant_config, node_key, node_config)
    end
  end
  def packer_gen(vm_config)
    # pp vm_config
    # if vm_config['packer']
    #   if vm_config['packer']['template']
    #     template_path = File.join($vagrant_root_dir,vm_config['packer']['template'])
    #     packer_definition = load_yaml(template_path, vm_config)
    #     packer_definition['provisioners'] = packer_definition['provisioners'] + vm_config['packer']['provisioners']
    #     vm_hash_id = "#{vm_config['lib']['key']}.#{vm_config['lib']['namespace']}"
    #     if vm_config['packer']['template_output_dir']
    #       file_path=File.join(vm_config['packer']['template_output_dir'], "#{vm_hash_id}.json")
    #       dir_path=File.dirname(file_path)
    #       FileUtils.mkdir_p(dir_path) unless File.exists?(dir_path)
    #       File.write(file_path, JSON.pretty_generate(packer_definition))
    #       File.write(File.join(file_path), JSON.pretty_generate(packer_definition))
    #     end
    #     log_to_file("packer/#{vm_config['lib']['namespace']}/#{vm_config['lib']['key']}.yaml", packer_definition.sort_by_key(true).to_h.to_yaml)
    #     log_to_file("packer/#{vm_config['lib']['namespace']}/#{vm_config['lib']['key']}.json", JSON.pretty_generate(packer_definition))
    #   end
    # end
  end
def configure_node(vagrant_config, node_key, node_config)
  # puts "configure #{node_key}"
  vagrant_config.vm.define node_key, autostart: node_config['autostart'] || false do |node|
    map(node_config['ssh'], node.ssh)
    map(node_config['winrm'], node.winrm)
    map(node_config['winssh'], node.winssh)
    vm_config = node_config['vm']
    node_providers = vm_config['provider']
    node_provisions = node_config['provision']
    vm = node.vm
    config_hook.call(node_config, node)
    map(vm_config, vm)
    node_providers.each do |provider_name, node_provider|
      node.vm.provider provider_name do |provider|
        if provider_name == "virtualbox"
          # provider.name = "boxes-#{node_key}"
        end
        if provider_name == "virtualbox" && node_provider.has_key?("_customize")
          node_provider['_customize'].each do |key, value|
            provider.customize ["modifyvm", :id, "--#{key}", "#{value}"]
          end
        end
        map(node_provider, provider, 'object')
      end
    end
    unless node_provisions.nil?
      # pp node_provisions.values
      # try to order priorities


      node_provisions.each do |node_provision|
        # p "provision type #{provision_name} #{node_provision['_type']}"
        if node_provision['_type']
          node.vm.provision node_provision['_type'] do |provisioner|

            extra_vars = {}
            node_config_variables = object_clone(node_config['variables']) ||
            node_provision_variables = object_clone(node_provision['variables'])

            # puts "########################################"
            # puts "#{node_config['_key']} node_config_variables="
            # pp node_config_variables
            # puts "########################################"
            # puts "#{node_config['_key']} node_provision_variables="
            # pp node_provision_variables

            if node_config_variables.nil?
              if !node_provision_variables.nil?
                extra_vars = node_provision_variables
              end
            else
              if node_provision_variables.nil?
                extra_vars = node_config_variables
              else
                extra_vars = node_config_variables.deep_merge(node_provision_variables)
              end
            end
            # puts "########################################"
            # puts "#{node_config['_key']} extra_vars="
            # pp extra_vars


            if node_provision['_type'] == 'shell'
              provisioner.name = node_provision['_key']
              # provisioner.env = extra_vars
            end
            if node_provision['_type'] == 'ansible' || node_provision['_type'] == 'ansible_local'
              provisioner.extra_vars = extra_vars.to_h

            end
            # removing extra_vars because already assigned
            node_provision_copy = object_clone(node_provision)
            # node_config_current
            node_provision['extra_vars'] = object_clone(extra_vars).sort_by_key(true).to_h
            # node_provision_copy.delete(:extra_vars)
            # puts "#{node_key} #{node_provision['extra_vars']}"
            map(node_provision_copy, provisioner, 'instance')
          end
        else
          puts "provision skipped #{node_provision} for #{node_key}"
        end

      end
    end

    unless vm_config['synced_folder'].nil?
      synced_folder = vm_config['synced_folder']
      synced_folder.each do |synced_folder_key, synced_folder_config|
        target_config = {}
        # map(synced_folder_config, target_config)
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
    end

    unless vm_config['networks'].nil?
      networks = vm_config['networks']
      networks.each do |network_config_key, network_config|
          case network_config['_type']
          when 'forwarded_port'
            network_config['ports'].each do |forwarded_port_config|
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
            vm.network "public_network", ip: public_network_config['ip'], bridge: public_network_config['bridge'], use_dhcp_assigned_default_route: public_network_config['use_dhcp_assigned_default_route']
          else
            # warn "#{network_config_key} is not a valid network identifier".red
          end
      end
    end
    # keep it for hostmanager ?
    # vm.network "private_network", type: "dhcp"
    # vm.network "private_network", type: "dhcp", virtualbox__intnet: node_config['_namespace'] || "internal"
  end
end

end