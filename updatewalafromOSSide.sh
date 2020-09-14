#!/bin/bash 
#########################################################################################################
# Description:  Update walinuxagent from repository or, if latest version not available, from github  	#
# Author: 		Marin Nedea																				#
# Created: 		Sep 14th, 2020									       									#
# Usage:  		Just run the script with sh (e.g. sh script.sh)           								#
# Requires:		AzCli 2.0 installed on the machine you're running this script on						#
# 				https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest		#
# 				If enabled, you can run it through the bash Cloud Shell in your Azure Portal page.		#
# WARNING:		Tested only with CentOS/RHEL 7+, SLES 12+, Oracle 7+, Debian 9+, Ubuntu 16.04 +.		#
#########################################################################################################

# Log execution
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/wala_update.log 2>&1
set -x 

# Get latest walinuxagent version from github (see https://github.com/Azure/WALinuxAgent/releases/latest )
lastwala=$(curl -s https://github.com/Azure/WALinuxAgent/releases/latest | grep -o -P '(?<=v).*(?=\")')

# Check running waaagent version
waagentrunning=$(waagent --version | head -n1 | awk '{print $1}' | awk -F"-" '{print $2}')

# Get the distribution name
DISTR=$(( lsb_release -ds || cat /etc/*release || uname -om ) 2>/dev/null | head -n1 | awk '{print $1}')

# Pure bash functions to compare versions
vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

do_vercomp () {
  vercomp $1 $2
    case $? in
        0) op='=';;
        1) op='>';;
        2) op='<';;
    esac
    if [[ $op == $3 ]] 
    then		
		echo "FAIL: '$1 $op $2'"
		upagent="1"        
    else
        echo "Pass: '$1 $op $2'"
		upagent="0"
		exit 0
    fi
}

# Install waagent from github function
walainstall () {
	systemctl stop $agentname 					  
	# Backup existing WALinuxAgent files
	mv /var/lib/waagent  /var/lib/waagentBACKUP
	# Install WALinuxAgent 			
	wget https://github.com/Azure/WALinuxAgent/archive/v$lastwala.zip
	unzip v$lastwala.zip
	cd WALinuxAgent-$lastwala
	[[ $pvers == "2" ]] && 	python setup.py install || python3 setup.py install
	# Start it back
	systemctl daemon-reload
	systemctl start $agentname
	# Restore ovf-env.xml from backup
	sleep 10
	cp /var/lib/waagentBACKUP/ovf-env.xml /var/lib/waagent/ovf-env.xml
	# Restart WALinuxAgent
	systemctl restart $agentname 
	# Get the running agent version after update
	waagentrunning=$(waagent --version | head -n1 | awk '{print $1}' | awk -F"-" '{print $2}')
	
	# Check if is up-to-date post install
	do_vercomp $waagentrunning $lastwala "<"
	[[ $upagent == "0" ]] && echo "WALinuxAgent is now up-to-date" || echo "WALinuxAgent update failed"
	exit 0
}

# Compare versions
do_vercomp $waagentrunning $lastwala "<"
if [[ $upagent == "1" ]]; then
# Check prerequisites:
pvers=$(python -c 'import sys; print(".".join(map(str, sys.version_info[:1])))')
	if [[ $pvers == "2" ]] ; then
	# verify pip 
	pipcheck=$(python -m pip -V | grep -i "not installed")		
		if [[ ! -z $pipcheck ]] ; then 
			echo "Prerequisites OK"
			installwalinux="1"
			pipinst="0"	
		else
			echo "Prerequisites NOT OK"
			installwalinux="0"
			pipinst="1"			
		fi		
	elif [[ $pvers == "3" ]] ; then	
		echo "Prerequisites OK"
		installwalinux="1"
		pipinst="0"
	fi

	if [[ $pipinst == "1" ]] ; then
		case $DISTR in
		 [Uu]buntu|[Dd]ebian)
			echo "Ubuntu/Debian"			  
			# Install prerequisites
			apt-get install python-pip wget unzip -y
			pip install --upgrade pip setuptools wheel
			installwalinux="1"			  
			;;
		 [Cc]ent[Oo][Ss]|rhel|[Rr]ed[Hh]at|[Oo]racle)
			echo "RedHat/CentOS/Oracle"
			# Install prerequisites			  
			cd /tmp
			wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
			yum install epel-release-latest-7.noarch.rpm -y
			yum install python-pip python-wheel python-setuptools wget unzip -y 				  
			installwalinux="1"
			;;
		 [Ss]use|SLES|sles)
			echo "SLES"
			# Install prerequisites
			zypper install python-pip wget unzip -y
			pip install --upgrade pip setuptools wheel
			installwalinux="1"		  
			;; 
		 *)
			echo "Unknown distribution. Aborting"
			installwalinux="0"
			exit 0
			;;
		esac
	fi

	if [[ $installwalinux == "1" ]]; then		
		case $DISTR in
		 [Uu]buntu)
			echo "Ubuntu"
			agentname="walinuxagent"		  
			walainstall 		  
			;;
		 [Dd]ebian)
			echo "Debian"
			agentname="waagent"
			walainstall		  
			;;
		 [Cc]ent[Oo][Ss]|rhel|[Rr]ed[Hh]at|[Oo]racle)
			echo "RedHat/CentOS/Oracle"
			agentname="waagent"
			walainstall
			;;
		 [Ss]use|SLES|sles)
			echo "SLES"
			agentname="waagent"
			walainstall
			;; 
		 *)
			echo "Unknown distribution. Aborting"
			exit 0
			;;
		esac
	fi
fi
exit 0
