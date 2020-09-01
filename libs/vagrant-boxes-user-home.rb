def user_create(vm, username)
  $script = <<-SCRIPT
  useradd --create-home --shell /bin/bash #{username}
  echo "%#{username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/#{username}
  SCRIPT
  vm.provision "shell", name: "vagrant-boxe-create-user", run: 'always', inline: $script
end

def home_rsync(vm, username)
  $script = <<-SCRIPT
  # id -u #{username} &>/dev/null || useradd -m --shell /bin/bash #{username}
  useradd --create-home --shell /bin/bash #{username}
  echo "%#{username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/#{username}
  SCRIPT
  vm.provision "shell", name: "vagrant-boxes-user-home #{username}", run: 'always', inline: $script

  vm.synced_folder  ENV['HOME'], "/home/#{username}", type: 'rsync', owner: "#{username}", group: "#{username}"
  # vm.synced_folder  ENV['HOME'], "/home/#{username}",
  #                       type: 'rsync',
  #                       owner: "#{username}",
  #                       group: "#{username}",
  #                       rsync__exclude: [".ssh/authorized_keys",".ssh/known_hosts",".gem",".berkshelf","bash_history", ".m2"]
end
def home_sync(vm, username)
  if File.exists?(ENV['HOME'])
    $script = <<-SCRIPT
  # id -u #{username} &>/dev/null || useradd -m --shell /bin/bash #{username}
  useradd --create-home --shell /bin/bash #{username}
  echo "%#{username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/#{username}
  sudo mount -t vboxsf -o uid=`id -u #{username}`,gid=`id -g #{username}`,dmode=700,fmode=700 #{username}_home /home/#{username}
  sudo mount -t vboxsf -o uid=`id -u #{username}`,gid=`id -g root`,dmode=700,fmode=600 #{username}_ssh /home/#{username}/.ssh
  SCRIPT
  vm.synced_folder "#{ENV['HOME']}", "/#{username}_home" # (in the Vagrantfile)
  vm.synced_folder "#{ENV['HOME']}/.ssh", "/#{username}_ssh" # (in the Vagrantfile)
  vm.provision "shell", name: "vagrant-boxes-user-home #{username}", run: 'always', inline: $script
  else
    raise "Environment variable HOME=#{ENV['HOME']} is not a valid path}"
  end
end