# shell provisioner based on configuration
def provision_shell(box, key, shell_config, vm_config)
  properties = [
    'args',
    'binary',
    'inline',
    'keep_color',
    'md5',
    'path',
    'powershell_args',
    'powershell_elevated_interactive',
    'run',
    'sha1',
    'sensitive',
    'upload_path'
    ]
  box.vm.provision :shell do |shell|
    shell.env = vm_config.deep_merge(shell_config['env'] || {})
    set_instance_variable(shell_config, shell, 'privileged', true)
    set_instance_variable(shell_config, shell, 'name', key)
    properties.each do | property_name |
      set_instance_variable(shell_config, shell,property_name )
    end
  end
end
# ansible provisioner helper to set common values
def provision_ansible_common(ansible, key, ansible_config, vm_config)
  # extra var is special, it is a merge from vm_config and extra_vars object
  extra_vars = {}
  # if ansible_config['extra_vars']
  #   extra_vars = ansible_config['extra_vars'].deep_merge(vm_config['variables'] || {})
  # else
  #   extra_vars = vm_config['variables'] || {}
  # end
  # pp vm_config
  if vm_config['variables']
    # puts "merge variables"
    extra_vars = vm_config['variables'].deep_merge(ansible_config['extra_vars'] || {})
  else
    # puts "no variables"
    extra_vars = ansible_config['extra_vars'] || {}
  end
  
  # pp extra_vars
  ansible.extra_vars = extra_vars
  set_instance_variable(ansible_config, ansible,'compatibility_mode', '2.0')
  set_instance_variable(ansible_config, ansible,'config_file', File.join(@boxes_root_dir, '/provision/ansible/ansible.cfg'))

  puts "#############################"
  puts "#############################"

  properties = [
    'become',
    'become_user',
    'galaxy_command',
    'galaxy_role_file',
    'galaxy_roles_path',
    'groups',
    'host_vars',
    'inventory_path',
    'limit',
    'playbook_command',
    'raw_arguments',
    'skip_tags',
    'start_at_task',
    'sudo',
    'sudo_user',
    'tags',
    'vault_password_file',
    'verbose',
    'version'
    ]
    properties.each do | property_name |
      set_instance_variable(ansible_config, ansible, property_name )
    end
end
# ansible local provisioner from configuration
def provision_ansible_local(box, key, ansible_config, vm_config)
  box.vm.provision :ansible_local do |ansible|
    provision_ansible_common(ansible, key, ansible_config, vm_config)
    properties = [
      'install',
      'install_mode',
      'provisioning_path',
      'tmp_path',
      'playbook'
    ]
    properties.each do | property_name |
      set_instance_variable(ansible_config, ansible, property_name )
    end
  end
end
# ansible provisioner from configuration
def provision_ansible(box, key, ansible_config, vm_config)
  box.vm.provision :ansible_local do |ansible|
    properties = [
      'ask_become_pass',
      'ask_sudo_pass',
      'ask_vault_pass',
      'force_remote_user',
      'host_key_checking',
      'raw_ssh_args'
    ]
    properties.each do | property_name |
      set_instance_variable(ansible_config, ansible, property_name )
    end
    provision_ansible_common(ansible, key, ansible_config, vm_config)
  end
end
# chef provisioner helper to set common values
def provision_chef_common(chef, key, chef_config, vm_config)
  # set_instance_variable(chef_config, chef, 'environment', '_default' )
  # set_instance_variable(chef_config, chef, 'version', '12.19.36' )
  properties = [
    'attempts',
    'enable_reporting',
    'encrypted_data_bag_secret_key_path',
    'environment',
    'run_list',
    'verbose_logging',
    'version'
  ]
  properties.each do | property_name |
    set_instance_variable(chef_config, chef, property_name )
  end
end
# chef zero provisioner from configuration
def provision_chef_zero(box, key, chef_config, vm_config)
  box.vm.provision "chef_zero" do |chef|
    set_instance_variable(chef_config, chef, 'cookbooks_path')
    set_instance_variable(chef_config, chef, 'data_bags_path')
    set_instance_variable(chef_config, chef, 'environments_path')
    set_instance_variable(chef_config, chef, 'nodes_path')
    set_instance_variable(chef_config, chef, 'roles_path')
    set_instance_variable(chef_config, chef, 'synced_folder_type')
    provision_chef_common(chef, key, chef_config, vm_config)
  end
end
# chef solo provisioner from configuration
def provision_chef_solo(box, key, chef_config, vm_config)
  box.vm.provision "chef_solo" do |chef|
    set_instance_variable(chef_config, chef, 'cookbooks_path')
    set_instance_variable(chef_config, chef, 'data_bags_path')
    set_instance_variable(chef_config, chef, 'environments_path')
    set_instance_variable(chef_config, chef, 'nodes_path')
    set_instance_variable(chef_config, chef, 'roles_path')
    set_instance_variable(chef_config, chef, 'synced_folder_type')
    provision_chef_common(chef, key, chef_config, vm_config)
  end
end
# chef client provisioner from configuration
def provision_chef_client(box, key, chef_config, vm_config)
  box.vm.provision "chef_client" do |chef|
    set_instance_variable(chef_config, chef, 'chef_server_url')
    set_instance_variable(chef_config, chef, 'validation_key_path')
    set_instance_variable(chef_config, chef, 'delete_node', true)
    set_instance_variable(chef_config, chef, 'delete_client', true)
    provision_chef_common(chef, key, chef_config, vm_config)
  end
end