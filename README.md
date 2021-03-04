## ANFCapacityReport
A PowerShell script to check and remediate capacity issues with Azure NetApp Files volumes.

### Install the Az.NetAppFiles PowerShell Module
Install-Module -Name Az.NetAppFiles -AllowClobber -Force

### Clone this respository
git clone https://github.com/ANFTechTeam/ANFCapacityReport.git

### Change directory to ANFCapacityReport
cd ANFCapacityReport

### Run the script in report only mode
./ANFCapacityReport.ps1

### Run the script and ignore failed volumes
./ANFCapacityReport.ps1 -IgnoreFailedVolumes

### Specify a custom volume percent full threshold (default is 80%)
./ANFCapacityReport.ps1 -PercentFullThreshold 75

### Run the script in remediate mode to fix volumes above specified threshold
./ANFCapacityReport.ps1 -Remediate

### Run the script with all options
./ANFCapacityReport.ps1 -IgnoreFailedVolumes -PercentFullThreshold 75 -Remediate

### Sample Output
![Sample Output](../img/../ANFCapacityReport/img/reportonly.png).