function Invoke-NinjaOneOrgMappingTenant {
    [CmdletBinding()]
    param (
        $QueueItem
    )

    $Tenant = $QueueItem.M365Tenant
    $NinjaOrgs = $QueueItem.NinjaOrgs
    $NinjaDevices = $QueueItem.NinjaDevices

    Write-Host "Processing $($Tenant.displayName)"

    $CIPPMapping = Get-CIPPTable -TableName CippMapping

    $TenantFilter = $Tenant.customerId

    $M365DevicesRaw = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices" -Tenantid $tenantfilter

    $M365Devices = foreach ($Device in $M365DevicesRaw) {
        [pscustomobject]@{
            'DeviceID'     = $Device.id
            'DeviceName'   = $Device.deviceName
            'DeviceSerial' = $Device.serialNumber
        }
    }


    [System.Collections.Generic.List[PSCustomObject]]$MatchedDevices = @()

    # Match devices on serial
    $DevicesToMatchSerial = $M365Devices | where-object { $null -ne $_.DeviceSerial }
    foreach ($SerialMatchDevice in $DevicesToMatchSerial) {
        $MatchedDevice = $NinjaDevices | where-object { $_.Serial -eq $SerialMatchDevice.DeviceSerial -or $_.BiosSerialNumber -eq $SerialMatchDevice.DeviceSerial }
        if (($MatchedDevice | measure-object).count -eq 1) {
            $Match = [pscustomobject]@{
                M365  = $SerialMatchDevice
                Ninja = $MatchedDevice
            }
            $MatchedDevices.add($Match)
        }
    }

    # Try to match on Name
    $DevicesToMatchName = $M365Devices | where-object { $_ -notin $MatchedDevices.M365 }
    foreach ($NameMatchDevice in $DevicesToMatchName) {
        $MatchedDevice = $NinjaDevices | where-object { $_.SystemName -eq $NameMatchDevice.DeviceName -or $_.DNSName -eq $NameMatchDevice.DeviceName }
        if (($MatchedDevice | measure-object).count -eq 1) {
            $Match = [pscustomobject]@{
                M365  = $NameMatchDevice
                Ninja = $MatchedDevice
            }
            $MatchedDevices.add($Match)
        }
    }


    # Match on the Org with the most devices that match
    if (($MatchedDevices.Ninja.ID | Measure-Object).Count -eq 1) {
        $MatchedOrgID = ($MatchedDevices.Ninja | group-object OrgID | sort-object Count -desc)[0].name
        $MatchedOrg = $NinjaOrgs | Where-Object { $_.id -eq $MatchedOrgID }

        $AddObject = @{
            PartitionKey   = 'NinjaOrgsMapping'
            RowKey         = "$($Tenant.customerId)"
            'NinjaOne'     = "$($MatchedOrg.id)"
            'NinjaOneName' = "$($MatchedOrg.name)"
        }
        Add-AzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API 'NinjaOneAutoMap_Queue' -user 'CIPP' -message "Added mapping from Device match for $($Tenant.displayName) to $($($MatchedOrg.name))" -Sev 'Info' 

    }

}