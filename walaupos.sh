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

# Compare version function 1

ver () { 
	printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

# vercomp () {
#     if [[ $1 == $2 ]]
#     then
#         return 0
#     fi
#     local IFS=.
#     local i ver1=($1) ver2=($2)
#     # fill empty fields in ver1 with zeros
#     for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
#     do
#         ver1[i]=0
#     done
#     for ((i=0; i<${#ver1[@]}; i++))
#     do
#         if [[ -z ${ver2[i]} ]]
#         then
#             # fill empty fields in ver2 with zeros
#             ver2[i]=0
#         fi
#         if ((10#${ver1[i]} > 10#${ver2[i]}))
#         then
#             return 1
#         fi
#         if ((10#${ver1[i]} < 10#${ver2[i]}))
#         then
#             return 2
#         fi
#     done
#     return 0
# }
# # Compare version function 2
# do_vercomp () {
#   vercomp $1 $2
#     case $? in
#         0) op='=';;
#         1) op='>';;
#         2) op='<';;
#     esac
#     if [[ $op == $3 ]] 
#     then		
# 		echo "FAIL: '$1 $op $2'"
# 		echo "Agent needs updated"
# 		upagent="1"        
#     else
#         echo "Pass: '$1 $op $2'"
# 		echo "Agent already up-to-date"
# 		exit 0
#     fi
# }

# Install waagent from github function
walainstall () {	
	
	# Backup existing WALinuxAgent files
	cp /var/lib/waagent/ovf-env.xml /tmp/ovf-env.xml

	# Install WALinuxAgent 			
	wget https://github.com/Azure/WALinuxAgent/archive/v$lastwala.zip
	unzip v$lastwala.zip
	cd WALinuxAgent-$lastwala

	# Check which python is available
	which python3 > /dev/null 2>&1 && i="3"
	# python$i -c 'import sys; print(".".join(map(str, sys.version_info[:])))'

	# Run the installer
	python$i setup.py install

	# Restore ovf-env.xml from backup
	cp /tmp/ovf-env.xml /var/lib/waagent/ovf-env.xml
	
	# Restart WALinuxAgent
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
		# echo "Ubuntu/Debian"
		agentname="walinuxagent"	
		! which curl   && apt-get install -y curl
		! which wget   && apt-get install -y wget
		! which unzip  && apt-get install -y unzip
		;;
	[Cc]ent[Oo][Ss]|[Oo]racle)
		# echo "RedHat/CentOS/Oracle"
		agentname="waagent"
		! which curl   && yum install -y curl
		! which wget   && yum install -y wget
		! which unzip  && yum install -y unzip
		;;
	rhel|red|Red|[Rr]ed[Hh]at)
		# echo "RedHat"
		agentname="waagent"
		wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
		yum install epel-release-latest-7.noarch.rpm -y
		! which curl   && yum install -y --enablerepo=epel curl
		! which wget   && yum install -y --enablerepo=epel wget
		! which unzip  && yum install -y --enablerepo=epel unzip
		;;
	[Ss][Uu][Ss][Ee]|SLES|sles)
		# echo "SLES"
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

[ $(ver ${waagentrunning}) -lt $(ver  ${lastwala}) ] && echo "Agent needs updated" && upagent="1" || echo "Agent is updated.Aborting." && exit 0

##############################
###	PREREQUISITES CHECK    ###
##############################
pipcheck=$(python -m pip -V | grep -i "not installed")
[[ -z "$pipcheck"  ]] && pipinstall

############################
###		INSTALL AGENT    ###
############################
[[ $upagent == "1" ]] && walainstall 

systemctl restart $agentname

exit 0
