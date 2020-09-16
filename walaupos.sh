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
#set -x

###########################
###	FUNCTIONS	###
###########################

# Compare versions function (only works with numbers)
ver () { 
	printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

# remove existing walinuagent 
restartagentcron () {
	#write out current crontab
	crontab -l > /tmp/mycron
	#echo new cron into cron file

	case ${DISTR} in
	[Uu]buntu|[Dd]ebian)
		echo "*/10 * * * *  systemctl restart walinuxagent ; crontab -l | grep -v walinuxagent | crontab -" >> mycron		
		;;
	*)
		echo "*/10 * * * *  systemctl restart waagent ; crontab -l | grep -v waagent | crontab -" >> mycron	
	;;
	esac
	#install new cron file
	crontab /tmp/mycron
	crontab -l
	rm /tmp/mycron
}

# Install waagent from github function
walainstall () {	
	echo "Agent needs updated" 
	# Backup existing WALinuxAgent files
	echo "Backin-up ovf-env.xml"
	cp /var/lib/waagent/ovf-env.xml /tmp/ovf-env.xml

	# Install WALinuxAgent 		
	echo "Downloading latest waagent release"	
	wget https://github.com/Azure/WALinuxAgent/archive/v${lastwala}.zip 2>/dev/null
	echo "Extracting ${lastwala}.zip"
	unzip v$lastwala.zip
	echo "Starting installation"
	cd WALinuxAgent-${lastwala}

	# Run the installer
	python setup.py install

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
	case ${DISTR} in
	[Uu]buntu|[Dd]ebian)
		apt-get install python-pip -y 
		pip install --upgrade pip setuptools
		;;
	[Cc]ent[Oo][Ss]|[Oo]racle|rhel|[Rr]ed|[Rr]ed[Hh]at)
		wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 2>/dev/null
		yum install epel-release-latest-7.noarch.rpm -y
		yum install python-setuptools -y
		yum remove epel-release -y
		;;
	[Ss][Uu][Ss][Ee]|SLES|sles)
		 zypper -n install python-pip
		 pip install --upgrade pip setuptools	  
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
		! which curl   && apt-get install -y curl
		! which wget   && apt-get install -y wget
		! which unzip  && apt-get install -y unzip
		;;
	[Cc]ent[Oo][Ss]|[Oo]racle)
		echo "CentOS/Oracle"
		! which curl   && yum install -y curl
		! which wget   && yum install -y wget
		! which unzip  && yum install -y unzip
		;;
	[Rr][Hh][Ee][Ll]|[Rr]ed|[Rr]ed[Hh]at)
		echo "RedHat"
		curl -o epel-release-latest-7.noarch.rpm  https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 2>/dev/null
		yum install epel-release-latest-7.noarch.rpm -y
		! which wget   && yum install -y --enablerepo=epel wget
		! which unzip  && yum install -y --enablerepo=epel unzip
		yum remove epel-release -y
		;;
	[Ss][Uu][Ss][Ee]|[Ss][Ll][Ee][Ss])
		echo "SLES"
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

workingdir=$(pwd)

# Make sure autoupdate is disabled to avoid download bug. 
oldstring=$(grep AutoUpdate.Enabled /etc/waagent.conf)
sed -i -e "s/${oldstring}/AutoUpdate.Enabled=n/g" /etc/waagent.conf

###########################
###	DISTRO CHECK	###
###########################
DISTR=$(cat /etc/*release | grep -i pretty | awk -F"\"" '{print $2}' | awk '{print $1}')
distrocheck 

###########################
###	AGENT CHECK	###
###########################

# Get latest walinuxagent version from github (see https://github.com/Azure/WALinuxAgent/releases/latest )
lastwala=$(curl -s https://github.com/Azure/WALinuxAgent/releases/latest 2>/dev/null | grep -o -P '(?<=v).*(?=\")')

# Check running waaagent version
waagentrunning=$(waagent --version | head -n1 | awk '{print $1}' | awk -F"-" '{print $2}')

# Compare versions
# do_vercomp $waagentrunning $lastwala "<"
echo "Comparing agent running version with available one"
[ $(ver ${waagentrunning}) -lt $(ver  ${lastwala}) ] && upagent="1" ||  upagent="0"

##############################
###   PREREQUISITES CHECK  ###
##############################
echo "Checking pip"
pipcheck=$(python -m pip -V | grep -i "not installed")
[[ -z "${pipcheck}"  ]] && pipinstall || echo "pip is available"

############################
###	INSTALL AGENT    ###
############################
[[ "${upagent}" == "1" ]] && walainstall || echo "Agent is updated already."

cd ${workingdir}
waagentrunning=$(waagent --version 2> /dev/null | head -n1 | awk '{print $1}' | awk -F"-" '{print $2}')
[[ ! -z ${waagentrunning} ]] && echo "Running agent version is now -- ${waagentrunning} -- " >> stdout

echo "Restarting agent 30 seconds after this script completes.
	  This should give enough time to Custom Script Extension to report status 
	  and also to the waagent to comunicate with the portal the new version."
restartagentcron

echo "All done, exiting."
exit 0
