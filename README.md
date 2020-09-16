# DESCRIPTION
This script will compare running WaLinuxAgent version to the latest available in and if needed, will attempt updating it on the VM.

# REQUIREMENT
- AzCli 2.0 installed on the machine you're running this script on <https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest>
- If enabled, you can run this script also through the bash Cloud Shell in your Azure Portal page.

# IMPORTANT
Please note the following software, if missing, will be installed on your VMs:
- wget
- curl
- unzip
- python-setuptools
- temporarily, on CentOS and RedHat machines, the epel repository will be enabled

# USAGE
- download walaupdatelinux.sh on a machine where AzCLI is running and up-to-date:

      wget https://raw.githubusercontent.com/marinnedea/walaupdate/master/walaupdatelinux.sh
        
- make the script executable:

      chmod +x walaupdatelinux.sh
        
- execute the script:

      ./walaupdatelinux.sh
       
# DISCLAIMER: 
This script is provided as it is and without any warranty. 
Neither the authot or the company the author of this script works for at this moment, or will work in the future, can be held responsible for any
harm this script may cause. 
USE IT AT YOUR OWN RISK!
