function Invoke-NinjaOneOrgMapping {
    <#
    .SYNOPSIS
        Auto-maps CIPP tenants to NinjaOne organizations by exact name, then by matching devices
    .DESCRIPTION
        Unmapped tenants are matched to a NinjaOne organization whose name exactly matches the tenant display name.
        Tenants still unmatched are matched to the organization owning most of their Intune devices (by serial,
        then device name), read from the ManagedDevices report cache. Existing mappings are never overwritten.
        Runs from the mapping page and, with -NameOnly, from the extension timer.
    .PARAMETER NameOnly
        Skip the device match, which downloads every NinjaOne device
    #>
    [CmdletBinding()]
    param(
        [switch]$NameOnly
    )

    $ExcludeSerials = @('0', 'SystemSerialNumber', 'To Be Filled By O.E.M.', 'System Serial Number', '0123456789', '123456789', '............')
    $CIPPMapping = Get-CIPPTable -TableName CippMapping

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne
    $Token = Get-NinjaOneToken -configuration $Configuration

    $Mappings = @(Get-ExtensionMapping -Extension 'NinjaOne')
    $MappedTenantIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Mappings.RowKey), [System.StringComparer]::OrdinalIgnoreCase)
    $MappedOrgIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Mappings.IntegrationId))

    $After = 0
    $PageSize = 1000
    $NinjaOrgs = do {
        $Result = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/organizations?pageSize=$PageSize&after=$After" -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
        $Result
        $ResultCount = ($Result.id | Measure-Object -Maximum)
        $After = $ResultCount.maximum
    } while ($ResultCount.count -eq $PageSize)

    $OrgsById = @{}
    $OrgsByName = @{}
    foreach ($Org in $NinjaOrgs) {
        $OrgsById["$($Org.id)"] = $Org
        $Name = "$($Org.name)".Trim()
        if (!$Name) { continue }
        if (!$OrgsByName.ContainsKey($Name)) { $OrgsByName[$Name] = [System.Collections.Generic.List[object]]::new() }
        $OrgsByName[$Name].Add($Org)
    }

    $Matched = 0
    $AddMapping = {
        param($Tenant, $Org, $MatchType)
        $AddObject = @{
            PartitionKey    = 'NinjaOneMapping'
            RowKey          = "$($Tenant.customerId)"
            IntegrationId   = "$($Org.id)"
            IntegrationName = "$($Org.name)"
        }
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        [void]$MappedOrgIds.Add("$($Org.id)")
        Write-LogMessage -API 'NinjaOneAutoMap' -tenant $Tenant.defaultDomainName -message "Mapped $($Tenant.displayName) to NinjaOne organization $($Org.name) by $MatchType match" -Sev 'Info'
    }

    $Unmatched = foreach ($Tenant in Get-Tenants -IncludeErrors) {
        if ($MappedTenantIds.Contains("$($Tenant.customerId)")) { continue }
        $NameMatches = $OrgsByName["$($Tenant.displayName)".Trim()]
        if ($NameMatches.Count -eq 1 -and !$MappedOrgIds.Contains("$($NameMatches[0].id)")) {
            & $AddMapping $Tenant $NameMatches[0] 'organization name'
            $Matched++
        } else {
            $Tenant
        }
    }

    if ($Unmatched -and !$NameOnly) {
        $After = 0
        $NinjaDevices = do {
            $Result = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/devices-detailed?pageSize=$PageSize&after=$After" -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
            $Result
            $ResultCount = ($Result.id | Measure-Object -Maximum)
            $After = $ResultCount.maximum
        } while ($ResultCount.count -eq $PageSize)

        # Key -> org id; a key seen in more than one org maps to $null so it never votes
        $OrgBySerial = @{}
        $OrgByName = @{}
        foreach ($Device in $NinjaDevices) {
            $OrgId = "$($Device.organizationId)"
            foreach ($Serial in @($Device.system.serialNumber, $Device.system.biosSerialNumber)) {
                if (!$Serial -or $Serial -in $ExcludeSerials) { continue }
                $OrgBySerial[$Serial] = if ($OrgBySerial.ContainsKey($Serial) -and $OrgBySerial[$Serial] -ne $OrgId) { $null } else { $OrgId }
            }
            foreach ($DeviceName in @($Device.systemName, $Device.dnsName)) {
                if (!$DeviceName) { continue }
                $OrgByName[$DeviceName] = if ($OrgByName.ContainsKey($DeviceName) -and $OrgByName[$DeviceName] -ne $OrgId) { $null } else { $OrgId }
            }
        }

        foreach ($Tenant in $Unmatched) {
            $Votes = @{}
            $Rows = try { Get-CIPPDbItem -TenantFilter $Tenant.defaultDomainName -Type 'ManagedDevices' } catch { continue }
            foreach ($Row in $Rows) {
                if ($Row.RowKey -like '*-Count') { continue }
                $IntuneDevice = [CIPP.CippJson]::ConvertFromJson($Row.Data, [string[]]@('deviceName', 'serialNumber'))
                $OrgId = if ($IntuneDevice.serialNumber -and $OrgBySerial[$IntuneDevice.serialNumber]) { $OrgBySerial[$IntuneDevice.serialNumber] } elseif ($IntuneDevice.deviceName) { $OrgByName[$IntuneDevice.deviceName] }
                if ($OrgId) { $Votes[$OrgId] = 1 + $Votes[$OrgId] }
            }
            if ($Votes.Count -eq 0) { continue }
            $Ranked = @($Votes.GetEnumerator() | Sort-Object Value -Descending)
            if ($Ranked.Count -gt 1 -and $Ranked[1].Value -eq $Ranked[0].Value) { continue }
            $Org = $OrgsById[$Ranked[0].Key]
            if (!$Org -or $MappedOrgIds.Contains("$($Org.id)")) { continue }
            & $AddMapping $Tenant $Org 'device'
            $Matched++
        }
    }

    if ($Matched -gt 0) {
        Write-LogMessage -API 'NinjaOneAutoMap' -message "NinjaOne AutoMap complete: $Matched tenant(s) mapped" -Sev 'Info'
    }
    return "NinjaOne AutoMap complete: $Matched new tenant mapping(s) added."
}
