#!/bin/bash
#########################################################################################################
# Description:  Find Windows Azure Agent version on all VMs in all subscriptions and updates it    	#
# Author: 	Marin Nedea										#
# Created: 	February 24th, 2023									#
# Usage:  	Just run the script with sh (e.g. sh script.sh)           				#
# Requires:	AzCli 2.0 installed on the machine you're running this script on			#
# 		https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest	#
# 		If enabled, you can run it through the bash Cloud Shell in your Azure Portal page.	#
#########################################################################################################

echo "DISCLAIMER: 
This script is provided as it is, and without any warranty. Neither the authot or the company the author 
of this script works for at this moment, or will work in the future, shall be held responsible about any
harm the incorrect usage of this script may cause."

# Login to the Azure account
az login

# Retrieve the list of all subscriptions in the Azure account
subscription_list=$(az account list --query "[].id" --output tsv)

# Initialize the list of VMs where the update couldn't be run due to permissions or version already up to date
vm_permission_error_list=""
vm_version_error_list=""

# Loop through all subscriptions
for subscription in $subscription_list; do
  # Set the default subscription
  az account set --subscription $subscription

  # Retrieve the list of all virtual machines in the subscription
  vm_list=$(az vm list --query "[].{Name:name, ResourceGroup:resourceGroup, OSType:storageProfile.osDisk.osType, Distro:storageProfile.imageReference.offer, PowerState:powerState.code}" --output tsv)

  # Loop through all virtual machines in the subscription
  while read -r vm_name vm_resource_group vm_os_type vm_distro vm_power_state; do
    if [ "$vm_power_state" != "running" ]; then
      # If the VM is not running, start it and wait until it is running
      az vm start --resource-group $vm_resource_group --name $vm_name --no-wait
      while [ "$vm_power_state" != "running" ]; do
        sleep 5
        vm_power_state=$(az vm show --resource-group $vm_resource_group --name $vm_name --query "powerState.code" --output tsv)
      done
    fi

    if [ "$vm_os_type" == "Linux" ]; then
      # Retrieve the latest stable release version of WaLinuxAgent from the official GitHub repository
      if ! command -v curl >/dev/null 2>&1; then
        # If curl is not installed on the VM, install it
        az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo apt-get update && sudo apt-get install curl -y" --no-wait
      fi
      latest_version=$(curl -s https://api.github.com/repos/Azure/WALinuxAgent/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

      # Check if the latest version is already installed on the VM
      installed_version=$(az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "waagent -version | grep -oP 'GuestAgent.*\K\d\.\d\.\d'" --query "value[0]" --output tsv)
      if [ "$latest_version" == "$installed_version" ]; then
        # If the latest version is already installed on the VM, add it to the list of VMs where the update couldn't be run due to version already up to date
        vm_version_error_list="$vm_version_error_list\nSubscription: $subscription, Resource Group: $vm_resource_group, VM: $vm_name"
        continue
      fi

      # Check if the latest version is available in the Linux distribution repository
      case "$vm_distro" in
        ubuntu)
          if ! command -v apt >/dev/null 2>&1; then
            # If apt is not installed on the VM, install it
            az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo apt-get update && sudo apt-get install apt -y" --no-wait
          fi
          available_version=$(apt-cache policy walinuxagent | grep Candidate | cut -d ":" -f 2 | sed 's/^[[:space:]]*//g')
          ;;
        debian)
          if ! command -v apt >/dev/null 2>&1; then
            # If apt is not installed on the VM, install it
            az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo apt-get update && sudo apt-get install apt -y" --no-wait
          fi
          available_version=$(apt-cache policy walinuxagent | grep Candidate | cut -d ":" -f 2 | sed 's/^[[:space:]]*//g')
          ;;
        redhat)
          if ! command -v yum >/dev/null 2>&1; then
            # If yum is not installed on the VM, install it
            az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo yum install yum-utils -y" --no-wait
          fi
          available_version=$(yum info walinuxagent | grep Version | head -1 | cut -d ":" -f 2 | sed 's/^[[:space:]]*//g')
          ;;
        centos)
          if ! command -v yum >/dev/null 2>&1; then
            # If yum is not installed on the VM, install it
            az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo yum install yum-utils -y" --no-wait
          fi
          available_version=$(yum info walinuxagent | grep Version | head -1 | cut -d ":" -f 2 | sed 's/^[[:space:]]*//g')
          ;;
        oracle)
          if ! command -v yum >/dev/null 2>&1; then
            # If yum is not installed on the VM, install it
            az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo yum install yum-utils -y" --no-wait
          fi
          available_version=$(yum info walinuxagent | grep Version | head -1 | cut -d ":" -f 2 | sed 's/^[[:space:]]*//g')
          ;;
        suse)
          if ! command -v zypper >/dev/null 2>&1; then
            # If zypper is not installed on the VM, install it
            az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo zypper install -y zypper" --no-wait
          fi
          available_version=$(zypper info walinuxagent | grep Version | head -1 | cut -d ":" -f 2 | sed 's/^[[:space:]]*//g')
          ;;
        rocky)
          if ! command -v yum >/dev/null 2>&1; then
            # If yum is not installed on the VM, install it
            az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo yum install yum-utils -y" --no-wait
          fi
          available_version=$(yum info walinuxagent | grep Version | head -1 | cut -d ":" -f 2 | sed 's/^[[:space:]]*//g')
          ;;
        *)
          echo "Unsupported Linux distribution: $vm_distro"
          continue
          ;;
      esac

      if [ "$latest_version" == "$installed_version" ] && [ "$latest_version" == "$available_version" ]; then
        # If the latest version is already installed on the VM and available in the Linux distribution repository, add it to the list of VMs where the update couldn't be run due to version already up to date
        vm_version_error_list="$vm_version_error_list\nSubscription: $subscription, Resource Group: $vm_resource_group, VM: $vm_name"
      elif [ "$latest_version" == "$available_version" ]; then
        # If the latest version is available in the Linux distribution repository, update it from the repository
        case "$vm_distro" in
          ubuntu)
            command='sudo apt-get update && sudo apt-get install walinuxagent'
            ;;
          debian)
            command='sudo apt-get update && sudo apt-get install walinuxagent'
            ;;
          redhat)
            command='sudo yum update waagent'
            ;;
          centos)
            command='sudo yum update waagent'
            ;;
          oracle)
            command='sudo yum update waagent'
            ;;
          suse)
            command='sudo zypper update walinuxagent'
            ;;
          rocky)
            command='sudo yum update waagent'
            ;;
          *)
            echo "Unsupported Linux distribution: $vm_distro"
            continue
            ;;
        esac
      else
        # If the latest version is not available in the Linux distribution repository, update it from the official GitHub repository
        if ! command -v curl >/dev/null 2>&1; then
          # If curl is not installed on the VM, install it
          az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "sudo apt-get update && sudo apt-get install curl -y" --no-wait
        fi
        command="sudo curl -L -o waagent.tar.gz https://github.com/Azure/WALinuxAgent/archive/$latest_version.tar.gz && sudo tar -zxvf waagent.tar.gz && cd WALinuxAgent-$latest_version && sudo python setup.py install"
      fi

      # Check if the user has the permissions to run the update command on the VM
      if az vm run-command list --resource-group $vm_resource_group --name $vm_name --query "[?name=='RunShellScript'].[id]" --output tsv >/dev/null 2>&1; then
        # Use AzCLI to execute the command on the VM
        az vm run-command invoke --resource-group $vm_resource_group --name $vm_name --command-id RunShellScript --scripts "$command" --no-wait
      else
        # If the user doesn't have the permissions to run the update command on the VM, add it to the list of VMs where the update couldn't be run due to permissions
        vm_permission_error_list="$vm_permission_error_list\nSubscription: $subscription, Resource Group: $vm_resource_group, VM: $vm_name"
      fi
    fi

    if [ "$vm_power_state" != "running" ]; then
      # If the VM was stopped before upgrading the WaLinuxAgent, stop it back
      az vm stop --resource-group $vm_resource_group --name $vm_name --no-wait
    fi
  done <<< "$vm_list"
done

# Logout from the Azure account - optional
# az logout

# Print the list of VMs where the update couldn't be run due to permissions or version already up to date
if [ "$vm_permission_error_list" != "" ]; then
  echo "The following VMs couldn't be updated due to permission errors:"
  echo -e "$vm_permission_error_list"
fi
if [ "$vm_version_error_list" != "" ]; then
  echo "The following VMs have the latest version already installed:"
  echo -e "$vm_version_error_list"
fi

