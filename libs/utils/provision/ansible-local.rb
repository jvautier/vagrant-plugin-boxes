#!/usr/bin/env ruby
require 'pathname'
require 'ipaddr'
require 'yaml'
require 'json'
require 'socket'
require 'open3'
require 'erb'
require 'pp'
require 'fileutils'

class AnsibleLocal

  def initialize()
  end
  def gen_provisions(source:, destination:, mount:, name_override:, ansible_version:, raw_arguments:)
    # puts "#{source} #{destination} #{mount} #{name_override}"
    mount_list = mount.split('|')
  
    provisioners = {}
    namespace_name = File.basename(source)
    if name_override && name_override != ""
      namespace_name=name_override
    end
    # ansible_version = ENV['ANSIBLE_VERSION']
    # ansible_version ||= "2.8.2"
  
    source_mount = source.gsub(mount_list[0], mount_list[1])
    pp source_mount
    Dir.glob("#{source}/*.yml") do |file|
  
      name = File.basename(file, ".*")
      if name == "requirements"
        next
      end
      puts "name=#{name}"
      filename = File.basename(file)
      config = {}
      config['_type'] = 'ansible_local'
      if File.file?(File.join(source, "ansible.yml"))
        config['config_file'] = "#{source_mount}/ansible.cfg"
      end
      config['provisioning_path'] = "#{source_mount}"
      config['playbook'] = filename
      config['version'] = ansible_version
      config['compatibility_mode'] = '2.0'
      config['install_mode'] = 'pip'
      
      if File.file?(File.join(source, "requirements.yml"))
        pp "Include galaxy command"
        config['galaxy_role_file'] = "#{source_mount}/requirements.yml"
        config['galaxy_roles_path'] = '/tmp/ansible-galaxy'
        config['galaxy_command'] = "sudo ansible-galaxy install --ignore-errors --role-file=%{role_file} --roles-path=%{roles_path}"
      else
        pp "Skip galaxy command"
      end
      config['extra_vars'] = {}
      config['extra_vars']['ansible_python_interpreter'] = '/usr/bin/python3'
      # config['raw_arguments'] = raw_arguments.split(',')


      provisioners[name] = config
    end
    dirname = File.dirname("#{destination}/#{namespace_name}.yml")
    unless File.directory?(dirname)
      FileUtils.mkdir_p(dirname)
    end
    # File.open("#{destination}/#{namespace_name}.yml", "w") { |file| file.puts provisioners.to_h.to_yaml}
    File.write("#{destination}/#{namespace_name}.yml", provisioners.to_h.to_yaml)
  end

end

if $0 == __FILE__
  p = AnsibleLocal.new()
  p.gen_provisions(source: ARGV[0], destination: ARGV[1], mount:ARGV[2], name_override: ARGV[3], ansible_version: ARGV[4], raw_arguments: ARGV[5])
end