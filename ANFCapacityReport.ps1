param (
    [switch]$IgnoreFailedVolumes = $false,
    [string]$PercentFullThreshold = 80,
    [switch]$Remediate = $false
 )


#$PercentFullThreshold = 13 #must be greater than 5 less than 100
$newVolumeCapacities = @{}
$netAppAccounts = Get-AzResource | Where-Object {$_.ResourceType -eq "Microsoft.NetApp/netAppAccounts"}
$capacityPools = Get-AzResource | Where-Object {$_.ResourceType -eq "Microsoft.NetApp/netAppAccounts/capacityPools"}
$volumes = Get-AzResource | Where-Object {$_.ResourceType -eq "Microsoft.NetApp/netAppAccounts/capacityPools/volumes"}
Write-Host ''
Write-Host 'Created by Sean Luce, https://seanluce.com'
Write-Host '****************************************************************************************' -ForegroundColor Yellow
Write-Host '****************************************************************************************' -ForegroundColor Yellow
Write-Host 'Azure NetApp Files - Hard Quotas - Beginning April 1st, 2021'
Write-Host 'With the volume hard quota change, Azure NetApp Files volumes will'
Write-Host 'no longer be thin provisioned at (the maximum) 100 TiB.'
Write-Host 'The volumes will be provisioned at the actual configured size (quota).'
Write-Host 'Also, the underlaying capacity pools will no longer automatically' 
Write-Host 'grow upon reaching full-capacity consumption.'
Write-Host 'This change will reflect the behavior like Azure managed disks,'
Write-Host 'which are also provisioned as-is, without automatic capacity increase.'
Write-Host 'https://docs.microsoft.com/en-us/azure/azure-netapp-files/volume-hard-quota-guidelines' -ForegroundColor Blue
Write-Host '****************************************************************************************' -ForegroundColor Yellow
Write-Host '****************************************************************************************' -ForegroundColor Yellow
Write-Host ''


Write-Host '**********************************************************' -ForegroundColor Yellow
Write-Host 'Target Volume full threshold for remediation: '$PercentFullThreshold'%' -ForegroundColor Yellow
Write-Host '**********************************************************' -ForegroundColor Yellow
Write-Host 'This value can be modified using the -PercentFullThreshold flag.' -ForegroundColor Yellow
Write-Host ''

## Collect all Capacity Pool Provisioned Sizes ##
$poolCapacities = @{}
Write-Host '** Collecting provisioned sizes for all Azure NetApp Files capacity pools. **' -ForegroundColor Green
foreach($capacityPool in $capacityPools) {
    $poolDetails = Get-AzNetAppFilesPool -ResourceId $capacityPool.ResourceId
    $poolCapacities.add($capacityPool.ResourceId, $poolDetails.Size / 1024 / 1024 / 1024)
}
## Collect all Capacity Pool Provisioned Sizes ##

## Collect all Volume Provisioned Capacities ##
$volumeCapacities = @{}
Write-Host '** Collecting provisioned sizes for all Azure NetApp Files volumes. **' -ForegroundColor Green
foreach($volume in $volumes) {
    $volumeDetails = Get-AzNetAppFilesVolume -ResourceId $volume.ResourceId
    if($volumeDetails.ProvisioningState -eq "Failed" -and $IgnoreFailedVolumes -eq $false) {
        Write-Host "Volumes in a 'Failed' state have been detected." -ForegroundColor Red
        Write-Host 'Please work with Microsoft Support to correct this issue before proceeding or use the -IgnoreFailedVolumes flag. Exiting.' -ForegroundColor Red
        exit
    } else {
    $volumeCapacities.add($volume.ResourceId, $volumeDetails.UsageThreshold / 1024 / 1024 / 1024)
    }
}
## Collect all Volume Provisioned Capacities ##

## Collect all Volume Consumed Sizes ##
Write-Host '** Collecting consumed sizes for all Azure NetApp Files volumes. **' -ForegroundColor Green
$volumeConsumedSizes = @{}
$startTime = [datetime]::Now.AddMinutes(-30)
$endTime = [datetime]::Now
foreach($volume in $volumes) {
    $consumedSize = 0
    $volumeConsumedDataPoints = Get-AzMetric -ResourceId $volume.ResourceId -MetricName "VolumeLogicalSize" -StartTime $startTime -EndTime $endTime -TimeGrain 00:5:00 -WarningAction:SilentlyContinue
    foreach($dataPoint in $volumeConsumedDataPoints.data) {
        if($dataPoint.Average -gt $consumedSize) {
            $consumedSize = $dataPoint.Average
        }
    }
    $VolumeConsumedSizes.add($volume.ResourceId, $consumedSize / 1024 / 1024 / 1024)
}
## Collect all Volume Consumed Sizes ##
Write-Host ''
Write-Host '*******************************************************' -ForegroundColor Yellow
Write-Host 'Target Volume full threshold for remediation:'$PercentFullThreshold'%' -ForegroundColor Yellow
Write-Host '*******************************************************' -ForegroundColor Yellow
Write-Host ''

## Get List of Unique Regions ##
$netAppRegions = @()
foreach($netAppAccount in $netAppAccounts) {
    $netAppRegions += $netAppAccount.Location
}
$netAppRegions = $netAppRegions | Sort-Object -Unique
## Get List of Unique Regions

## Display Azure NetApp Files Hierarchy
' '
foreach($netAppRegion in $netAppRegions) {
    $netAppRegion
    foreach($netAppAccount in $netAppAccounts | Where-Object {$_.Location -eq $netAppRegion}) {
        Write-Host '|--' $netappAccount.Name ' (NetApp Account)' -ForegroundColor Yellow
        foreach($capacityPool in $capacityPools | Where-Object {$_.Location -eq $netAppRegion -and $_.Name.Split("/")[0] -eq $netAppAccount.Name}) {
            $poolError = 0
            $poolTotalAllocated = 0
            $poolTotalConsumed = 0
            $newPoolTotalAllocated = 0
            Write-Host '  |--' $capacityPool.Name.Split("/")[1] '('$poolDetails.QosType'QoS Pool,'$poolCapacities[$capacityPool.ResourceId]'GiB )' -ForegroundColor Magenta
            foreach($volume in $volumes | Where-Object {$_.Location -eq $netAppRegion -and $_.Name.Split("/")[1] -eq $capacityPool.Name.Split("/")[1]}) {
                $displayConsumed = 0
                $errorCondition = 0
                if($volumeConsumedSizes[$volume.ResourceId] -lt 1) {
                    $displayConsumed = 'less than 1'
                } else {
                    $displayConsumed = [math]::Round($volumeConsumedSizes[$volume.ResourceId],2)
                }
                $percentConsumed = ($volumeConsumedSizes[$volume.ResourceId] / $volumeCapacities[$volume.ResourceId]) * 100
                if($percentConsumed -lt 1) {
                    $displayPercentConsumed = '<1'
                } else {
                    $displayPercentConsumed = [math]::Round($percentConsumed,0)
                }
                if($percentConsumed -ge $PercentFullThreshold) {
                    $errorCondition = 1
                    $newVolumeQuota = [math]::Round($volumeConsumedSizes[$volume.ResourceId] * (100/($PercentFullThreshold-3)),0)
                    if($newVolumeQuota -gt 102400) {
                        $errorCondition = 2
                        $poolError = 2
                    } else {
                        $newVolumeCapacities.add($volume.ResourceId, $newVolumeQuota)
                        $poolError = 1
                    }
                } else {
                    $newVolumeCapacities.add($volume.ResourceId, $volumeCapacities[$volume.ResourceId])
                }
                if($errorCondition -eq 0) {
                    Write-Host '    |--' $volume.Name.Split("/")[2]'(Consuming'$displayConsumed' GiB of provisioned' $volumeCapacities[$volume.ResourceId]'GiB,'$displayPercentConsumed'% consumed)'
                } elseif($errorCondition -eq 1) {
                    Write-Host '    |--' $volume.Name.Split("/")[2]'**WARNING**'$displayConsumed'% consumed exceeds '$PercentFullThreshold'% threshold. Current Size:' $volumeCapacities[$volume.ResourceId]'GiB, Suggested size:'$newVolumeQuota' GiB' -ForegroundColor Yellow
                } elseif($errorCondition -eq 2) {
                    if($volumeCapacities[$volume.ResourceId -gt 102400]) {
                        Write-Host 'Current volume consumption is greater than maximium of 100TiB, please contact Microsoft Support.' -ForegroundColor Red
                    } else {
                    Write-Host '    |--' $volume.Name.Split("/")[2]'(Consuming'$displayConsumed' GiB of provisioned' $volumeCapacities[$volume.ResourceId]'GiB,'$displayPercentConsumed'% consumed) **CRITICAL** Suggested volume size exceeds 100TiB max volume size.' -ForegroundColor Red
                    }
                }
                $poolTotalAllocated += $volumeCapacities[$volume.ResourceId]
                $poolTotalConsumed += $volumeConsumedSizes[$volume.ResourceId]
            }
            Write-Host '  Total Pool Capacity Allocated to Volumes: '$poolTotalAllocated' GiB' -ForegroundColor Magenta
            $displayTotalPoolConsumed = [math]::Round($poolTotalConsumed,2)
            Write-Host '  Total Actual Consumed in Pool    : '$displayTotalPoolConsumed' GiB' -ForegroundColor Magenta
            if($poolError -eq 0) {
                Write-Host '  No capacity issues found. No corrective action needed for this pool.' -ForegroundColor Green
            } elseif($poolError -eq 1) {
                Write-Host '  Capacity issues found. Corrective action needed for this pool.' -ForegroundColor Red
                if($Remediate -eq $true) {
                    foreach($volume in $volumes | Where-Object {$_.Location -eq $netAppRegion -and $_.Name.Split("/")[1] -eq $capacityPool.Name.Split("/")[1]}) {
                        $newPoolTotalAllocated += $newVolumeCapacities[$volume.ResourceId]
                    }
                    if($newPoolTotalAllocated -gt $poolCapacities[$capacityPool.ResourceId]) {
                        $poolSizeinTiB = $poolCapacities[$capacityPool.ResourceId] / 1024
                        Write-Host '  New Total Allocated to Volumes:'$newPoolTotalAllocated' GiB' -ForegroundColor Red
                        Write-Host '  Existing Pool Size:'$poolCapacities[$capacityPool.ResourceId]'GIB ('$poolSizeinTiB' TiB )' -ForegroundColor Red
                        $newPoolSizeinGiB = $newPoolTotalAllocated - ($newPoolTotalAllocated % 1024) + 1024
                        $newPoolSizeinTiB = $newPoolSizeinGiB / 1024
                        $newPoolSizeinBytes = $newPoolSizeinGiB * 1024 * 1024 * 1024
                        Write-Host '  Pool size will need to be increased to accomodate new volume sizes. Suggested size:'$newPoolSizeinGiB' GiB ( '$newPoolSizeinTiB' TiB )' -Foreground Red
                        $continue = Read-Host -Prompt "  To continue with suggested pool size increase, enter 'yes'"
                        if($continue -eq 'yes') {
                            Write-Host '  Resizing Capacity Pool...' -ForegroundColor Red
                            Update-AzNetAppFilesPool -ResourceId $capacityPool.ResourceId -PoolSize $newPoolSizeinBytes
                        } else {
                            break
                        }
                    }
                 else {
                    Write-Host '  Existing pool size is large enough to accomodate new volume sizes.' -Foreground Green
                 }
                    $continue = Read-Host -Prompt "  To continue with suggested volume resize, enter 'yes'"
                    if($continue -eq 'yes') {
                        Write-Host '  Resizing Volumes...' -ForegroundColor Red
                        foreach($volume in $volumes | Where-Object {$_.Location -eq $netAppRegion -and $_.Name.Split("/")[1] -eq $capacityPool.Name.Split("/")[1]}) {
                            if($newVolumeCapacities[$volume.ResourceId] -gt $volumeCapacities[$volume.ResourceId]) {
                                Write-Host '    '$volume.Name': Increasing volume quota from'$volumeCapacities[$volume.ResourceId]'GiB to'$newVolumeCapacities[$volume.ResourceId]'GiB' -ForegroundColor Red
                                $newSizeinBytes = $newVolumeCapacities[$volume.ResourceId] * 1024 * 1024 * 1024
                                Update-AzNetAppFilesVolume -ResourceId $volume.ResourceId -UsageThreshold $newSizeinBytes
                            }
                        }
                    }
                
                
            } else {
                Write-Host ''
                Write-Host '  To remediate capacity issues, run this script again with the -Remediate flag.' -ForegroundColor Red
                Write-Host ''
            }
        } elseif($poolError -eq 2) {
            Write-Host '  Capacity issues found outside the scope of this script. Please contact Microsoft Support.' -ForegroundColor Red
        }
        }
        ' '
    }
    ' '
}
if($Remediate -eq $false) {
Write-Host '*** To remediate capacity issues, run this script again with the -Remediate flag. ***' -ForegroundColor Red
Write-Host ''
}
## Display Azure NetApp Files Hierarchy
