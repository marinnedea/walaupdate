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

# Get the distribution name
DISTR=$(cat /etc/*release | grep -i pretty | awk -F"\"" '{print $2}' | awk '{print $1}')

###########################
###	FUNCTIONS	###
###########################
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

rhel_repo_cert () {
	yum update -y --disablerepo='*' --enablerepo='*microsoft*'
	yum clean all
	yum makecache
}

rhel_non_eus () {
	FILE="/etc/yum/vars/releasever"
	[ -f "$FILE" ] && vlock="1" || vlock="0"

	if [[ "$vlock" == "1" ]]; then	
		mv /etc/yum/vars/releasever /tmp/releasever
		yum --disablerepo='*' remove 'rhui-azure-rhel7-eus' -y
		yum --config='https://rhelimage.blob.core.windows.net/repositories/rhui-microsoft-azure-rhel7.config' install 'rhui-azure-rhel7' -y
	elif [[  "$vlock" == "0"  ]] ; then
		rhel_repo_cert
	fi
} 

rhel_eus () {
	FILE="/tmp/releasever"
	[ -f "$FILE" ] && eus="1"
	if [[ "$eus" == "1" ]] ; then
	yum --disablerepo='*' remove 'rhui-azure-rhel7' -y 
	yum --config='https://rhelimage.blob.core.windows.net/repositories/rhui-microsoft-azure-rhel7-eus.config' install 'rhui-azure-rhel7-eus' -y
	cp $FILE > /etc/yum/vars/releasever
	yum clean all
	yum makecache
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
	systemctl restart $agentname
	# Restore ovf-env.xml from backup
	sleep 10
	cp /var/lib/waagentBACKUP/ovf-env.xml /var/lib/waagent/ovf-env.xml
	
	# Restart WALinuxAgent
	systemctl daemon-reload
	systemctl restart $agentname 
}

###########################
###	DISTRO CHECK	###
###########################

case $DISTR in
 [Uu]buntu|[Dd]ebian)
	echo "Ubuntu/Debian"
	agentname="walinuxagent"
	apt-get install curl wget unzip -y
	;;
 [Cc]ent[Oo][Ss]|[Oo]racle)
 	echo "RedHat/CentOS/Oracle"
	agentname="waagent"
	yum install curl wget unzip -y
	;;
 rhel|red|Red|[Rr]ed[Hh]at)
 	echo "RedHat"
	agentname="waagent"
	rhel_non_eus
	yum install curl wget unzip -y
	rhel_eus
	;;
 [Ss][Uu][Ss][Ee]|SLES|sles)
	echo "SLES"
	agentname="waagent"
	# -n = non-interactive (https://unix.stackexchange.com/questions/82016/how-to-use-zypper-in-bash-scripts-for-someone-coming-from-apt-get)
	zypper -n install curl wget unzip
	;;
 *)
	echo "Unknown distribution. Aborting"
	exit 0
	;;
esac

###########################
###	AGENT CHECK	###
###########################

# Get latest walinuxagent version from github (see https://github.com/Azure/WALinuxAgent/releases/latest )
lastwala=$(curl -s https://github.com/Azure/WALinuxAgent/releases/latest | grep -o -P '(?<=v).*(?=\")')

#Make sure autoupdate is enabled
oldstring=$(grep AutoUpdate.Enabled /etc/waagent.conf)
sed -i -e "s/${oldstring}/AutoUpdate.Enabled=y/g" /etc/waagent.conf
systemctl daemon-reload
systemctl restart $agentname

# Check running waaagent version
waagentrunning=$(waagent --version | head -n1 | awk '{print $1}' | awk -F"-" '{print $2}')

# Compare versions
do_vercomp $waagentrunning $lastwala "<"

###########################
###	PREREQUISITES	###
###########################

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
		 [Cc]ent[Oo][Ss]|[Oo]racle)
			echo "RedHat/CentOS/Oracle"
			# Install prerequisites			  
			cd /tmp
			yum install wget unzip -y
			wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
			yum install epel-release-latest-7.noarch.rpm -y
			yum install python-pip python-wheel python-setuptools -y 				  
			installwalinux="1"
			;;
		 rhel|red|Red|[Rr]ed[Hh]at)
			echo "RedHat"
			agentname="waagent"
			rhel_non_eus
		 	cd /tmp
			yum install wget unzip -y
			wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
			yum install epel-release-latest-7.noarch.rpm -y
			yum install python-pip python-wheel python-setuptools -y 	
			rhel_eus
			installwalinux="1"
			;;
		 [Ss][Uu][Ss][Ee]|SLES|sles)
			echo "SLES"
			# Install prerequisites
			zypper -n install python-pip
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
fi

###########################
###	INSTALL AGENT	###
###########################

# If all checks-up, install the agent
[[ $installwalinux == "1" ]] && walainstall 
exit 0
