# # array concat if value is not nill or empty
def concat_array(array)
  box_name = array.reject { |c| c.nil? || c.empty? }.join('.')
end
# # box name helper using vm_config
# def get_box_name(vm_config)
#   box_hostname = concat_array( 
#     [
#     vm_config['key'],
#     vm_config['namespace']
#     ]
#   )
#   return box_hostname
# end
# # box hostname helper using vm_config
# def get_box_hostname_from_config(vm_config)
#   box_hostname = concat_array( 
#     [
#     vm_config['key'],
#     vm_config['namespace'],
#     vm_config['domain']
#     ]
#   )
#   return box_hostname
# end
def get_box_name(vm_config)
  box_hostname = concat_array( 
    [
    vm_config['lib']['key'],
    vm_config['lib']['namespace']
    ]
  )
  return box_hostname
end
# box hostname helper using vm_config
def get_box_hostname_from_config(node_config)
  
  box_hostname = concat_array( 
    [
      node_config['lib']['key'],
      node_config['lib']['namespace'],
      node_config['variables'] && node_config['variables']['domain'] ? node_config['variables']['domain'] : ''
    ]
  )
  return box_hostname
end
# helper resolving ips for hostmanager
def read_ip_address(machine)
  command =  "ip a | grep 'inet' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $2 }' | cut -f1 -d\"/\""
  result = ""
  $logger.info "Processing #{ machine.name } ... "
  begin
    # sudo is needed for ifconfig
    machine.communicate.sudo(command) do |type, data|
      result << data if type == :stdout
    end
    $logger.info "Processing #{ machine.name } ... success"
  rescue
    result = "# NOT-UP"
    $logger.info "Processing #{ machine.name } ... not running"
  end
  # the second inet is more accurate
  result.chomp.split("\n").select { |hash| hash != "" }[1]
end
# helper to check if private ips are colliding
def check_private_ips
  $vms.each do |key,vm_config|
    if !vm_config['private_network_ip'].to_s.empty?
      $vms.each do |key_search,vm_config_search|
          if vm_config['private_network_ip'] == vm_config_search['private_network_ip']
            if key != key_search
              warn "you have a ip conflict between #{vm_config['key']} and #{vm_config_search['name']}".red
            end
          end
        end
      end
    end
end