#!/bin/bash 
#########################################################################################################
# Description:  Update walinuxagent from repository or, if latest version not available, from github  	#
# Author: 	Marin Nedea										#
# Created: 	Sep 14th, 2020									   	#
# Usage:  	Just run the script with sh (e.g. sh script.sh)           				#
# Requires:	AzCli 2.0 installed on the machine you're running this script on			#
# 		https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest	#
# 		If enabled, you can run it through the bash Cloud Shell in your Azure Portal page.	#
# WARNING:	Tested only with CentOS/RHEL 7+, SLES 12+, Oracle 7+, Debian 9+, Ubuntu 16.04 +.	#
#########################################################################################################

# Log execution
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/wala_update.log 2>&1
set -x

###########################
###	FUNCTIONS	###
###########################

# Compare versions function (only works with numbers)
ver () { 
	printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

# Install waagent from github function
walainstall () {	
	
	# Backup existing WALinuxAgent files
	echo "Backin-up ovf-env.xml"
	cp /var/lib/waagent/ovf-env.xml /tmp/ovf-env.xml

	# Install WALinuxAgent 		
	echo "Downloading latest waagent release"	
	wget https://github.com/Azure/WALinuxAgent/archive/v$lastwala.zip
	
	echo "Extracting ${lastwala}.zip"
	unzip v$lastwala.zip
	

	# Check which python is available
	echo "Starting installation"
	cd WALinuxAgent-$lastwala
	which python3 > /dev/null 2>&1 && i="3"
	# python$i -c 'import sys; print(".".join(map(str, sys.version_info[:])))'

	# Run the installer
	python$i setup.py install
	echo "Installation completed"
	
	# Restore ovf-env.xml from backup
	echo "Restoring ovf-env.xml file"
	cp /tmp/ovf-env.xml /var/lib/waagent/ovf-env.xml
	
	# Restart WALinuxAgent
	echo "Reloading daemons"
	systemctl daemon-reload
}

# Install pip, setuptools and wheel
pipinstall () {
	case $DISTR in
	[Uu]buntu|[Dd]ebian)
		which python3  && i="3"
		apt-get install python$i-pip -y
		pip$i install --upgrade pip setuptools wheel  
		;;
	[Cc]ent[Oo][Ss]|[Oo]racle|rhel|[Rr]ed|[Rr]ed[Hh]at)
		wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
		yum install epel-release-latest-7.noarch.rpm -y
		which python3  && i="3"
		yum install python$i-pip python$i-wheel python$i-setuptools -y 
		pip$i install --upgrade pip setuptools wheel				  	
		;;
	[Ss][Uu][Ss][Ee]|SLES|sles)
		which python3  && i="3"
		zypper -n install python$i-pip 
		pip$i install --upgrade pip setuptools wheel		  
		;; 
	*)
	echo "Unknown distribution. Aborting"
	exit 0
	;;
	esac
}

# Check distribution and install curl, wget and unzip if needed
distrocheck () {
	case $DISTR in
	[Uu]buntu|[Dd]ebian)
		echo "Ubuntu/Debian"
		agentname="walinuxagent"	
		! which curl   && apt-get install -y curl
		! which wget   && apt-get install -y wget
		! which unzip  && apt-get install -y unzip
		;;
	[Cc]ent[Oo][Ss]|[Oo]racle)
		echo "RedHat/CentOS/Oracle"
		agentname="waagent"
		! which curl   && yum install -y curl
		! which wget   && yum install -y wget
		! which unzip  && yum install -y unzip
		;;
	rhel|red|Red|[Rr]ed[Hh]at)
		echo "RedHat"
		agentname="waagent"
		wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
		yum install epel-release-latest-7.noarch.rpm -y
		! which curl   && yum install -y --enablerepo=epel curl
		! which wget   && yum install -y --enablerepo=epel wget
		! which unzip  && yum install -y --enablerepo=epel unzip
		;;
	[Ss][Uu][Ss][Ee]|SLES|sles)
		echo "SLES"
		agentname="waagent"
		! which curl   && zypper -n install curl
		! which wget   && zypper -n install wget
		! which unzip  && zypper -n install unzip
		;;
	*)
		echo "Unknown distribution. Aborting"
		exit 0
		;;
	esac
}

# Make sure autoupdate is enabled, so even if this script fails further, the agent may try to update itself automatically. 
oldstring=$(grep AutoUpdate.Enabled /etc/waagent.conf)
sed -i -e "s/${oldstring}/AutoUpdate.Enabled=y/g" /etc/waagent.conf

###########################
###	DISTRO CHECK	###
###########################
DISTR=$(cat /etc/*release | grep -i pretty | awk -F"\"" '{print $2}' | awk '{print $1}')
distrocheck 

###########################
###	AGENT CHECK	###
###########################

# Get latest walinuxagent version from github (see https://github.com/Azure/WALinuxAgent/releases/latest )
lastwala=$(curl -s https://github.com/Azure/WALinuxAgent/releases/latest | grep -o -P '(?<=v).*(?=\")')

# Check running waaagent version
waagentrunning=$(waagent --version | head -n1 | awk '{print $1}' | awk -F"-" '{print $2}')

# Compare versions
# do_vercomp $waagentrunning $lastwala "<"
echo "Comparing agent running version with available one"
[ $(ver ${waagentrunning}) -lt $(ver  ${lastwala}) ] && echo "Agent needs updated" && upagent="1" || echo "Agent is updated.Aborting." && upagent="0"

##############################
###	PREREQUISITES CHECK    ###
##############################
echo "Checking pip"
pipcheck=$(python -m pip -V | grep -i "not installed")
[[ -z "$pipcheck"  ]] && pipinstall

############################
###		INSTALL AGENT    ###
############################
[[ $upagent == "1" ]] && walainstall

echo "Restarting agent for the last time."
systemctl restart $agentname

echo "All done, exiting."
exit 0
