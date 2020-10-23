#!/bin/bash
#########################################################################################################
# Description:  Find Windows Azure Agent version on all VMs in all subscriptions and updates it    		#
# Author: 	Marin Nedea										#
# Created: 	June 24th, 2020										#
# Usage:  	Just run the script with sh (e.g. sh script.sh)           				#
# Requires:	AzCli 2.0 installed on the machine you're running this script on			#
# 		https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest	#
# 		If enabled, you can run it through the bash Cloud Shell in your Azure Portal page.	#
#########################################################################################################

echo "DISCLAIMER: 
This script is provided as it is, and without any warranty. Neither the authot or the company the author 
of this script works for at this moment, or will work in the future, shall be held responsible about any
harm the incorrect usage of this script may cause.

Please note the following software, if missing, will be installed on your VMs:
- wget
- curl
- unzip
- python-setuptools

Also, temporarily, on CentOS and RedHat machines, the epel repository will be enabled."
echo ""
echo ""
read -p "Are you sure you wish to continue? " -n 1 -r
echo ""
echo ""
if [[ ${REPLY} =~ ^[Yy]$ ]] ; then
 
echo "Script starting"  
# CSV file:
csv_file=/tmp/azagentversion.csv
backup_file=/tmp/azagentversion.$(date +"%m-%d-%Y_%T" ).BKP.csv
csv_header="Subscription;ResourceGroup;VM Name;VM Power Status;OS type;Distro Name;OLD Agent version;NEW Agent version;Portal version;Agent status"

# Pure bash functions to compare versions
ver () { 
	printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

# Show execution on screen
#set -x

# Get latest walinuxagent version from github (see https://github.com/Azure/WALinuxAgent/releases/latest )
lastwala=$(curl -s https://github.com/Azure/WALinuxAgent/releases/latest | grep -o -P '(?<=v).*(?=\")')

# Create the csv file if does not exists; backup and create if already exist.
if [ ! -f ${csv_file} ]
then
    touch ${csv_file} && echo "Created ${csv_file}" 
	echo ""
	echo ""
else 
	mv  ${csv_file} ${backup_file} && echo "Created a backup of ${csv_file} as ${backup_file}" 
	echo ""
	echo ""
	touch ${csv_file} && echo "Created a new ${csv_file}"
	echo ""
	echo ""
fi
echo ${csv_header} > ${csv_file}

# Checking if there any account logged in azcli
if az account show > /dev/null 2>&1; then
	echo "You are already logged in."
else
	echo "Please login to Az CLI"
	az login
	echo ""
	echo ""
fi

echo "Please provide the subscription ID: "
read subID

az account set --subscription ${subID}

echo "Please provide the Resource Group Name: "
read rgName

echo "Please provide the VM Name: "
read vmName

					
echo "-- Checking vm: ${vmName}" 					

osversion="$(az vm get-instance-view -g ${rgName} -n ${vmName} | grep -i osType| awk -F '"' '{printf $4 "\n"}')"
echo "--- OS: ${osversion}"					

vmState="$(az vm show -g ${rgName} -n ${vmName} -d --query powerState -o tsv)"
echo "--- VM Power state: ${vmState}"					

agentversion=$(az vm get-instance-view --resource-group ${rgName} --name ${vmName} | grep -i vmagentversion | awk -F"\"" '{print $4}')
distroname=$(az vm  get-instance-view  --resource-group ${rgName} --name ${vmName} --query instanceView -o tsv | awk '{print $8" "$9}')

if [[ ${osversion} == "Linux" ]]
then
	if [[ ${vmState} == "VM running" ]]
	then
		if [[ -z ${agentversion} ]] || [[ ${agentversion} == "Unknown" ]]
		then
			echo "The VM ${vmName} is in running state but the WaLinuxAgent version is not reported."
			upagent="0"
			agentstate="Not Available"
		else
			if [ $(ver ${agentversion}) -lt $(ver ${lastwala}) ]
			then
				echo "Agent version ${agentversion} lower than ${lastwala}."
				upagent="1"
			elif [ $(ver ${agentversion}) -eq $(ver  ${lastwala}) ]
			then
				echo "WaLinuxAgent is already updated to version ${agentversion} on Linux VM ${vmName}"
				newagentversion=${agentversion}
				portalversion=${agentversion}
				upagent="0"
				agentstate="Ready"
			fi
		fi
	else
		echo "The VM ${vmName} is not pwered ON and couldn't retrieve the agent version"
		upagent="0"
		agentstate="Not Available"
	fi
fi

if [[ "${upagent}" == "1" ]]; then						
	echo "Updating the WaLinuxAgent on Linux VM ${vmName}, to version ${lastwala}."
	
	az vm run-command invoke --verbose -g ${rgName} -n ${vmName} --command-id RunShellScript --scripts '[ -x /usr/bin/curl ] && dlndr="curl -o " || dlndr="wget -O "; $dlndr walaupos.sh  https://raw.githubusercontent.com/marinnedea/walaupdate/master/walaupos.sh && sh walaupos.sh'  
	
fi
# Addding the results to the CSV file. 
echo "${subs};${rgName};${vmName};${vmState};${osversion};${distroname};${agentversion};${newagentversion};${portalversion};${agentstate}" >> ${csv_file}

exit 0