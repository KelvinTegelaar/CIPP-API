function Invoke-ListIntuneSettingDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the devices that have any of the given Intune policies, with each device's deployment status for that policy, for one tenant. Device configuration and compliance policies are read from the reporting database cache when it holds their device statuses, settings catalog policies when it holds their device report, other policies (or policies with nothing cached) are read live. Each row says which in Source (Cache or Live). A device name Intune leaves blank is filled from the managed device (reporting cache first, then Graph). Policy types Intune has no per-device status for (update profiles, hardware configurations, app protection) return no rows. A policy that fails to load does not stop the others: its message is in Metadata.Warnings and the status is 207, or 500 when every policy fails. At most 50 policies can be requested at once; split larger sets across requests.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $MaxPolicies = 50
    $MaxDeviceLookups = 100

    $TenantFilter = $Request.Query.tenantFilter
    # Comma-separated <URLName>:<PolicyId> pairs, e.g. deviceConfigurations:<guid>,configurationPolicies:<guid>
    $Policies = $Request.Query.Policies

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'A single tenant is required.' }
            })
    }

    $DefinitionById = @{}
    foreach ($Definition in @(Get-CIPPIntunePolicyListDefinitions)) { $DefinitionById[$Definition.Id] = $Definition }
    $Requested = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Invalid = [System.Collections.Generic.List[string]]::new()
    foreach ($RawEntry in "$Policies".Split(',')) {
        $Entry = $RawEntry.Trim()
        if (-not $Entry) { continue }
        $URLName, $PolicyId = $Entry -split ':', 2
        $Definition = $DefinitionById["$URLName"]
        # App protection ids carry a type prefix (T_<guid>, A_<guid>)
        if (-not $Definition -or "$PolicyId" -notmatch '^([A-Za-z]_)?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
            $Invalid.Add($Entry)
            continue
        }
        if ($Seen.Add("$($Definition.Id):$PolicyId")) {
            $Requested.Add([PSCustomObject]@{ URLName = $URLName; PolicyId = $PolicyId; Definition = $Definition })
        }
    }

    if ($Invalid.Count -gt 0 -or $Requested.Count -eq 0) {
        $Message = if ($Invalid.Count -gt 0) { "Invalid policies: $($Invalid -join ', '). Each must be <URLName>:<PolicyId> with a known policy type and a policy id." } else { 'At least one policy is required as <URLName>:<PolicyId>.' }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = $Message }
            })
    }

    if ($Requested.Count -gt $MaxPolicies) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Too many policies: $($Requested.Count) requested, at most $MaxPolicies are allowed per request." }
            })
    }

    $Partition = @(Get-Tenants -TenantFilter $TenantFilter)[0].defaultDomainName ?? $TenantFilter
    $DeviceStatusTypes = @('deviceConfigurations', 'deviceCompliancePolicies', 'mobileAppConfigurations')
    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $Unnamed = [System.Collections.Generic.List[object]]::new()
    $Rows = [System.Collections.Generic.List[object]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $FailedPolicies = 0
    foreach ($Policy in $Requested) {
        $IsCatalog = $Policy.Definition.Id -eq 'ConfigurationPolicies'
        $CacheType = if ($IsCatalog) { "IntuneConfigurationPolicyDevices_$($Policy.PolicyId)" } elseif ($Policy.Definition.FetchDeviceStatuses) { "$($Policy.Definition.CacheType)_$($Policy.PolicyId)" }
        $Cached = $null
        $HasCountRow = $false
        if ($CacheType) {
            try {
                $Cached = [System.Collections.Generic.List[object]]::new()
                foreach ($Item in @(Get-CIPPDbItem -Partition $Partition -Type $CacheType)) {
                    if ("$($Item.RowKey)".EndsWith('-Count')) { $HasCountRow = $true; continue }
                    $Cached.Add([CIPP.CippJson]::ConvertFromJson($Item.Data))
                }
            } catch {
                $Cached = $null
                $HasCountRow = $false
            }
        }

        $StatusParams = @{
            TenantFilter = $TenantFilter
            Type         = $Policy.Definition.Id
            Id           = $Policy.PolicyId
            DevicesOnly  = $true
        }
        $Source = 'Live'
        # A catalog count row makes an empty report authoritative; device statuses cache nothing for a policy without any
        if ($IsCatalog -and $HasCountRow) {
            $StatusParams.ReportRows = @($Cached)
            $Source = 'Cache'
        } elseif (-not $IsCatalog -and $Cached.Count -gt 0) {
            $StatusParams.DeviceStatuses = @($Cached)
            $Source = 'Cache'
        }

        try {
            $Status = Get-CIPPIntuneDeploymentStatus @StatusParams
        } catch {
            $Warnings.Add($_.Exception.Message)
            $FailedPolicies++
            continue
        }

        $IsStatusType = $Policy.Definition.Id -in $DeviceStatusTypes
        $SeenDeviceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Device in $Status.Devices) {
            if (-not $Device) { continue }
            # The cache keeps one status row per device, so live keeps the first too
            if ($IsStatusType -and $Device.DeviceId -and -not $SeenDeviceIds.Add([string]$Device.DeviceId)) { continue }
            $Row = [PSCustomObject]@{
                PolicyId          = $Policy.PolicyId
                URLName           = $Policy.URLName
                DeviceName        = $Device.DeviceName
                UserPrincipalName = $Device.UserPrincipalName
                Status            = $Device.Status
                StatusDetail      = $Device.StatusDetail
                Platform          = $Device.Platform
                LastReported      = $Device.LastReported
                Source            = $Source
            }
            # deviceStatuses report a device's own (device-targeted) status with no user
            if ($IsStatusType -and [string]::IsNullOrEmpty($Row.UserPrincipalName)) { $Row.UserPrincipalName = 'System account' }
            if ([string]::IsNullOrWhiteSpace($Row.DeviceName) -and "$($Device.DeviceId)" -match $GuidPattern) {
                $Unnamed.Add([PSCustomObject]@{ Row = $Row; DeviceId = "$($Device.DeviceId)" })
            }
            $Rows.Add($Row)
        }
    }

    # Intune can leave the device name empty on status rows, so it comes from the managed device
    if ($Unnamed.Count -gt 0) {
        $Wanted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Entry in $Unnamed) {
            if ($Wanted.Count -ge $MaxDeviceLookups) { break }
            $null = $Wanted.Add($Entry.DeviceId)
        }

        $ManagedDevices = @{}
        $Table = Get-CippTable -tablename 'CippReportingDB'
        $SafePartition = ConvertTo-CIPPODataFilterValue -Value $Partition -Type String
        foreach ($DeviceId in $Wanted) {
            try {
                # A range rather than eq, so an item split into '-partN' rows is read whole
                $Filter = "PartitionKey eq '{0}' and RowKey ge 'ManagedDevices-{1}' and RowKey lt 'ManagedDevices-{1}.'" -f $SafePartition, $DeviceId
                foreach ($Item in @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)) {
                    $ManagedDevice = [CIPP.CippJson]::ConvertFromJson($Item.Data)
                    if ($ManagedDevice.id -and $ManagedDevice.deviceName) { $ManagedDevices[$ManagedDevice.id] = $ManagedDevice }
                }
            } catch {
                continue
            }
        }

        $LiveRequests = foreach ($DeviceId in $Wanted) {
            if (-not $ManagedDevices.ContainsKey($DeviceId)) {
                @{ id = $DeviceId; method = 'GET'; url = "/deviceManagement/managedDevices/$($DeviceId)?`$select=id,deviceName,operatingSystem" }
            }
        }
        if ($LiveRequests) {
            try {
                foreach ($Result in @(New-GraphBulkRequest -Requests @($LiveRequests) -tenantid $TenantFilter)) {
                    if ($Result.body.id -and $Result.body.deviceName) { $ManagedDevices[$Result.body.id] = $Result.body }
                }
            } catch {
                $Warnings.Add("Could not look up the names of devices Intune reported without one: $($_.Exception.Message)")
            }
        }

        foreach ($Entry in $Unnamed) {
            $ManagedDevice = $ManagedDevices[$Entry.DeviceId]
            if (-not $ManagedDevice) { continue }
            $Entry.Row.DeviceName = $ManagedDevice.deviceName
            if ([string]::IsNullOrWhiteSpace($Entry.Row.Platform)) { $Entry.Row.Platform = $ManagedDevice.operatingSystem }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total $Requested.Count -Failed $FailedPolicies
            Body       = @{
                Results  = @($Rows)
                Metadata = @{ Warnings = @($Warnings) }
            }
        })
}
