# Ansible all hosts variables(vars)
#  PYTHONUNBUFFERED=1 ANSIBLE_FORCE_COLOR=true ANSIBLE_HOST_KEY_CHECKING=false ANSIBLE_SSH_ARGS='-o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o ControlMaster=auto -o ControlPersist=60s' ansible-playbook --connection=ssh --timeout=30  --limit="all" --inventory-file= /d/work_sync/Dome/mysql/mariadb/lab/.vagrant/provisioners/ansible/inventory --sudo -vv deploy_play.yml  --vault-password-file=.ck_vault_pass.txt
# Install the plugin with vagrant plugin install vagrant-disksize
# On ansible host you may need to set the following in file: /etc/ansible/ansible.cfg
#               [defaults]
#               interpreter_python = /usr/bin/python3.12

#  sudo apt install software-properties-common
#  sudo add-apt-repository --yes --update ppa:ansible/ansible
#  sudo apt install -y ansible
#  cp /mnt/c/Users/umeji/.vagrant.d/insecure_private_key /home/major/
#  chmod 600 insecure_private_key
# You may need to install python3 on remote host
# and also for almalinux 8 you may need to execute the command below:
# rpm --import https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux
# dnf upgrade almalinux-release
# dnf install python312 -y
# cd /mnt/d/work_sync/Dome/mysql/mariadb/lab/
# Edit the inventory file and change the path to the private_key and possibly the host ip address & ssh import
#  vim   /mnt/d/work_sync/Dome/mysql/mariadb/lab/.vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory
# np-mariadb-lvmv9-master001 ansible_ssh_host=10.3.0.61 ansible_ssh_port=22 ansible_ssh_user='vagrant' ansible_ssh_private_key_file='/home/major/insecure_private_key' host_ip=10.3.0.61
# np-mariadb-lvmv9-worker001 ansible_ssh_host=10.3.0.62 ansible_ssh_port=22 ansible_ssh_user='vagrant' ansible_ssh_private_key_file='/home/major/insecure_private_key' host_ip=10.3.0.62
# np-mariadb-lvmv9-worker002 ansible_ssh_host=10.3.0.63 ansible_ssh_port=22 ansible_ssh_user='vagrant' ansible_ssh_private_key_file='/home/major/insecure_private_key' host_ip=10.3.0.63

# Copy ansible-vault password file to: /home/major/.ck_vault_pass.txt

#  PYTHONUNBUFFERED=1 ANSIBLE_FORCE_COLOR=true ANSIBLE_HOST_KEY_CHECKING=false ANSIBLE_SSH_ARGS='-o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o ControlMaster=auto -o ControlPersist=60s' ansible-playbook --connection=ssh --timeout=30  --limit="all" --inventory-file=/mnt/d/work_sync/Dome/mysql/mariadb/lab/.vagrant/provisioners/ansible/inventory  -vv deploy_play.yml  --vault-password-file=.ck_vault_pass.txt   
# To log into the machines created by this Vagrant file do:
    # SHELL> ssh -i ~/.vagrant.d/insecure_private_key  vagrant@10.3.0.61

# Ansible worker group variables(vars)

# Lets create 2GB swapfile - https://programmaticponderings.com/2013/12/19/scripting-linux-swap-space/
# $script_create_swapfile = <<-SCRIPT
# #!/bin/sh

# # size of 2GB swapfile
# swapsize=2080

# # does the swap file already exist?
# grep -q "swapfile" /etc/fstab

# # if not then create it
# if [ $? -ne 0 ]; then
# 	echo 'swapfile not found. Adding swapfile.'
# 	fallocate -l ${swapsize}M /swapfile
# 	chmod 600 /swapfile
# 	mkswap /swapfile
# 	swapon /swapfile
# 	echo '/swapfile none swap defaults 0 0' >> /etc/fstab
# else
# 	echo 'swapfile found. No changes made.'
# fi

# # output results to terminal
# cat /proc/swaps
# cat /proc/meminfo | grep Swap
# SCRIPT


# vm_machines = [
#     {
#         :name       => "np-mariadb-lvmv9-master001",
#         :ip         => "10.3.0.61",
#     },
#     {
#         :name       => "np-mariadb-lvmv9-worker001",
#         :ip         => "10.3.0.62",
#     },
#     {
#         :name       => "np-mariadb-lvmv9-worker002",
#         :ip         => "10.3.0.63",
#     },
# ]


# Vagrant.configure("2") do |config|
#     # Base Vagrant VM configuration
#     # config.vm.box = "almalinux/8"
#     config.vm.box = "almalinux/9"
#     config.disksize.size = '70GB'
#     config.vm.provider "virtualbox" do |v|
#         v.customize ["modifyvm", :id, "--memory", "3072", "--cpus", "3"]
#     end
#     # Now execute script to create swapfile
#     config.vm.provision "shell", inline: $script_create_swapfile
#     config.ssh.insert_key = false
#     config.vm.synced_folder ".", "/vagrant", disabled: true
#     config.ssh.private_key_path = "~/.vagrant.d/insecure_private_key"
#     vm_machines.each do |vm_machine|
#         config.vm.define vm_machine[:name], primary: true do |vm_machine_config|
#             vm_machine_config.vm.hostname = vm_machine[:name]
#             vm_machine_config.vm.network "private_network", ip: vm_machine[:ip]
#                 if vm_machine[:name] == "np-mariadb-lvmv9-worker002"
#                     vm_machine_config.vm.provision "ansible" do |ansible|
#                         ansible.limit = "all"
#                         # ansible.install_mode = "pip"
#                         # ansible.version = "2.9.10"
#                         ansible.become = true
#                         ansible.playbook = "deploy_play.yml"
#                         ansible.groups = {
#                           "all:vars" => {
#                           },
#                           "master" => ["np-mariadb-lvmv9-master001"],
#                           "master:vars" => {
#                             "kube_master_node" => "True",
#                           },
#                            "worker" => (1..2).map{ |i| "np-mariadb-lvmv9-worker%03d" % i },
#                           "worker:vars" => {
#                             "kube_master_node" => "False",
#                           },
#                         }
#                         ansible.host_vars = {
#                             "np-mariadb-lvmv9-master001" => {"host_ip" => "10.3.0.61",},
#                             "np-mariadb-lvmv9-worker001" => {"host_ip" => "10.3.0.62",},
#                             "np-mariadb-lvmv9-worker002" => {"host_ip" => "10.3.0.63",},
#                         }
#                         ansible.verbose = "-vv"
#                     end
#             end
#         end
#     end
# end

VAGRANTFILE_API_VERSION = "2"

$script_create_swapfile = <<-SCRIPT
#!/bin/sh

swapsize=2080

grep -q "/swapfile" /etc/fstab

if [ $? -ne 0 ]; then
    echo "swapfile not found. Adding swapfile."

    fallocate -l ${swapsize}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    echo "/swapfile none swap defaults 0 0" >> /etc/fstab

    echo "✅ Swapfile created successfully."
else
    echo "✅ Swapfile already exists. No changes made."
fi

echo
echo "==================== SWAP INFORMATION ===================="

cat /proc/swaps

echo
cat /proc/meminfo | grep Swap

echo "==========================================================="
SCRIPT

vm_machines = [
    {
        :name => "np-mysql-lvmv9-master001",
        :ip   => "192.168.1.130",
    },
    {
        :name => "np-mysql-lvmv9-worker001",
        :ip   => "192.168.1.131",
    },
    # {
    #     :name => "np-mariadb-lvmv9-worker002",
    #     :ip   => "192.168.1.132",
    # },
]

Vagrant.configure("2") do |config|

    config.vm.box = "almalinux/9"

    config.disksize.size = "70GB"

    config.vm.provider "virtualbox" do |v|
        v.memory = 3072
        v.cpus   = 3
    end

    config.vm.synced_folder ".", "/vagrant", disabled: true

    vm_machines.each do |vm_machine|

        config.vm.define vm_machine[:name] do |vm|

            vm.vm.hostname = vm_machine[:name]

            vm.vm.network "public_network",
                ip: vm_machine[:ip]

            vm.vm.provision "shell",
                inline: $script_create_swapfile

        end
    end
end