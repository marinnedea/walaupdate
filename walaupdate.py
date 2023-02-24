import os
import subprocess

# Install necessary tools on the system
def install_tools():
    os.system('sudo apt-get update')
    os.system('sudo apt-get install -y curl unzip python-setuptools')
    os.system('sudo yum update -y')
    os.system('sudo yum install -y epel-release')
    os.system('sudo yum install -y curl unzip python-setuptools')

# Check if WaLinuxAgent is installed on the system and get its version
def get_installed_version():
    try:
        installed_version = subprocess.check_output(['/usr/sbin/waagent', '--version'])
        installed_version = installed_version.decode().split(':')[1].strip()
        return installed_version
    except subprocess.CalledProcessError:
        return None

# Check the latest WaLinuxAgent version available in Azure
def get_latest_version():
    latest_version = subprocess.check_output(['az', 'vm', 'run-command', 'invoke', '-g', 'MyResourceGroup', '-n', 'MyVmName', '--command-id', 'RunShellScript', '--scripts', 'sudo waagent -version | grep -oP \'(?<=WALinuxAgent-)\d+\.\d+\.\d+\''], stderr=subprocess.DEVNULL)
    latest_version = latest_version.decode().strip()
    return latest_version

# Update WaLinuxAgent to the latest version
def update_agent():
    os.system('curl -L -O https://github.com/Azure/WALinuxAgent/archive/v<latest_version>.tar.gz')
    os.system('tar -zxvf v<latest_version>.tar.gz')
    os.chdir('WALinuxAgent-<latest_version>/')
    os.system('sudo python setup.py install')

# Check and update WaLinuxAgent on all Linux VMs in all Azure subscriptions
def check_and_update_agents():
    # Get the list of Azure subscriptions
    subscriptions = subprocess.check_output(['az', 'account', 'list', '--query', '[].id', '--output', 'tsv']).decode().splitlines()

    for subscription in subscriptions:
        # Set the current subscription
        os.system('az account set --subscription ' + subscription)

        # Get the list of Linux VMs in the subscription
        vms = subprocess.check_output(['az', 'vm', 'list', '--query', '[?storageProfile.osDisk.osType==`Linux`].[name,resourceGroup]', '--output', 'tsv']).decode().splitlines()

        for vm in vms:
            vm_name, resource_group = vm.split('\t')

            # Set the current VM context
            os.system('az vm list-ip-addresses -g ' + resource_group + ' -n ' + vm_name + ' --query [0].virtualMachine.network.publicIpAddresses[0].ipAddress --output tsv')
            os.system('az vm user list -g ' + resource_group + ' -n ' + vm_name + ' --query [0].name --output tsv')

            # Check if WaLinuxAgent is installed and get its version
            installed_version = get_installed_version()

            # Get the latest WaLinuxAgent version available in Azure
            latest_version = get_latest_version()

            # Update WaLinuxAgent if a newer version is available
            if installed_version != latest_version:
                update_agent()

if __name__ == '__main__':
    install_tools()
    check_and_update_agents()
