# ANFCapacityReport

A PowerShell script to check and **optionally** remediate capacity issues with Azure NetApp Files volumes.

## Change Log
    3/24/2021 - Adding instructions to run against all Azure subscriptions (see below)

## Install the Az.NetAppFiles PowerShell Module

    Install-Module -Name Az.NetAppFiles -AllowClobber -Force

## Clone this respository

    git clone https://github.com/ANFTechTeam/ANFCapacityReport.git

## Change directory to ANFCapacityReport**

    cd ANFCapacityReport

## Run the script in report only mode

    ./ANFCapacityReport.ps1

## Run the script and ignore failed volumes

    ./ANFCapacityReport.ps1 -IgnoreFailedVolumes

## Specify a custom volume percent full threshold (default is 80%)

    ./ANFCapacityReport.ps1 -PercentFullThreshold 75

## Run the script in remediate mode to fix volumes above specified threshold

    ./ANFCapacityReport.ps1 -Remediate

## Run the script in remediate mode and automatically answer 'yes' to all resize prompts (non-interactive mode)

    ./ANFCapacityReport.ps1 -Remediate -Yes

## Run the script with all options

    ./ANFCapacityReport.ps1 -IgnoreFailedVolumes -PercentFullThreshold 75 -Remediate -Yes

## Run the script against all Azure subscriptions

    foreach($sub in Get-AzSubscription) { Set-AzContext $sub; ./ANFCapacityReport.ps1 -IgnoreFailedVolumes -PercentFullThreshold 75 }

## Sample Output

![Sample Output](https://github.com/ANFTechTeam/ANFCapacityReport/blob/main/img/reportonly.png)
