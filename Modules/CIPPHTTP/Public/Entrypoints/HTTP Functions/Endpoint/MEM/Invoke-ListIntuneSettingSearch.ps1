function Invoke-ListIntuneSettingSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Searches cached Intune policies (settings catalog, custom OMA-URI and property-based policies) for settings whose name or id contains the search text, case-insensitively. Returns one row per setting with the policies that configure it, sorted by setting name. PolicyTypes on each setting is the distinct policy types of its policies, sorted and comma separated. Reads the reporting database only. Works for a single tenant only: AllTenants returns 400 and an unknown tenant 404. A search shorter than 3 characters returns 400. At most 500 settings are returned; Metadata.Truncated is true when more matched. When truncated, the rows are the first 500 matching settings found in the cache, sorted by setting name, not the alphabetically first 500 of all matches. DeviceCount on each setting and on each of its Policies is the number of distinct devices in the cached device statuses or settings catalog device reports, and null when none of the policies has cached device data, such as policy types without a device report or policies not synced yet.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $MaxResults = 500
    # Above this many policies of one family, one range read of the family beats a read per policy
    $PerPolicyReadLimit = 5
    $CatalogDevicesType = 'IntuneConfigurationPolicyDevices'

    $TenantFilter = $Request.Query.tenantFilter
    $Search = "$($Request.Query.search)".Trim()

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Setting search works on one tenant at a time. Select a single tenant.' }
            })
    }

    if ($Search.Length -lt 3) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Enter at least 3 characters to search for a setting.' }
            })
    }

    try {
        $Partition = $null
        foreach ($Tenant in @(Get-Tenants -TenantFilter $TenantFilter)) { $Partition = $Tenant.defaultDomainName; break }
        if (-not $Partition) { throw [System.Management.Automation.ItemNotFoundException]::new("Tenant '$TenantFilter' not found.") }

        $DefinitionIndex = Get-CIPPIntuneDefinitionIndex
        $PolicyDefinitions = @(Get-CIPPIntunePolicyListDefinitions)
        $Groups = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $KeptSettingIds = $null

        foreach ($Definition in $PolicyDefinitions) {
            # Administrative Templates and Endpoint Security intents do not cache their settings
            if ($Definition.Id -eq 'GroupPolicyConfigurations' -or $Definition.Id -eq 'Intents') { continue }

            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Partition $Partition -Type $Definition.CacheType)) {
                if ($Item.RowKey -like '*-Count') { continue }
                try {
                    $Policy = [CIPP.CippJson]::ConvertFromJson($Item.Data)
                } catch {
                    Write-LogMessage -API 'IntuneSettingSearch' -tenant $TenantFilter -message "Failed to parse cached Intune policy item '$($Item.RowKey)' from '$($Definition.CacheType)': $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
                    continue
                }
                if ($null -eq $Policy) { continue }

                $ListItem = ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName $Definition.Id -DefaultPolicyTypeName $Definition.PolicyTypeName
                if ($null -eq $ListItem) { continue }

                $TypeLabel = if ($ListItem.PolicyTypeName) {
                    $ListItem.PolicyTypeName
                } elseif ($ListItem.'@odata.type') {
                    $ListItem.'@odata.type' -replace '^#?microsoft\.graph\.', ''
                } else {
                    $Definition.Id
                }
                $SettingParams = @{
                    Policy          = $ListItem
                    URLName         = $Definition.Id
                    PolicyTypeName  = $TypeLabel
                    DefinitionIndex = $DefinitionIndex
                    Search          = $Search
                }
                if ($null -ne $KeptSettingIds) { $SettingParams.SettingIds = $KeptSettingIds }

                $PolicyKey = [string]$ListItem.id
                foreach ($Setting in @(ConvertTo-CIPPIntunePolicySetting @SettingParams)) {
                    $Group = $Groups[$Setting.SettingId]
                    if ($null -eq $Group) {
                        if ($Groups.Count -gt $MaxResults) { continue }
                        $Group = [PSCustomObject]@{
                            SettingId    = $Setting.SettingId
                            SettingName  = $Setting.SettingName
                            Category     = $Setting.Category
                            Policies     = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
                            PolicyValues = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        }
                        $Groups[$Setting.SettingId] = $Group
                        # One setting past the cap shows that more matched; later policies only add to kept settings
                        if ($Groups.Count -gt $MaxResults) {
                            $KeptSettingIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Groups.Keys), [System.StringComparer]::OrdinalIgnoreCase)
                        }
                    }
                    $Existing = $Group.Policies[$PolicyKey]
                    if ($Existing) {
                        if ($Setting.Value -and $Group.PolicyValues[$PolicyKey].Add($Setting.Value)) {
                            $Existing.Value = if ($Existing.Value) { "$($Existing.Value), $($Setting.Value)" } else { $Setting.Value }
                        }
                        continue
                    }
                    $Group.PolicyValues[$PolicyKey] = [System.Collections.Generic.HashSet[string]]::new()
                    if ($Setting.Value) { $null = $Group.PolicyValues[$PolicyKey].Add($Setting.Value) }
                    $Group.Policies[$PolicyKey] = @{
                        PolicyId       = $PolicyKey
                        PolicyName     = [string]$ListItem.displayName
                        PolicyTypeName = [string]$ListItem.PolicyTypeName
                        URLName        = $Definition.Id
                        Value          = $Setting.Value
                    }
                }
            }
        }

        $Truncated = $Groups.Count -gt $MaxResults
        $Kept = @($Groups.Values | Sort-Object -Property SettingName, SettingId)
        if ($Truncated) { $Kept = $Kept[0..($MaxResults - 1)] }

        # Any cached row of a policy, even only its count row, makes its device count 0 rather than null
        $DevicesByPolicy = @{}
        try {
            $TypeByUrlName = @{}
            foreach ($Definition in $PolicyDefinitions) {
                if ($Definition.Id -eq 'ConfigurationPolicies') {
                    $TypeByUrlName[$Definition.Id] = $CatalogDevicesType
                } elseif ($Definition.FetchDeviceStatuses) {
                    $TypeByUrlName[$Definition.Id] = $Definition.CacheType
                }
            }

            $PolicyIdsByType = @{}
            foreach ($Group in $Kept) {
                foreach ($Policy in $Group.Policies.Values) {
                    $Type = $TypeByUrlName[[string]$Policy.URLName]
                    if (-not $Type -or $Policy.PolicyId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { continue }
                    if (-not $PolicyIdsByType.ContainsKey($Type)) { $PolicyIdsByType[$Type] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
                    $null = $PolicyIdsByType[$Type].Add($Policy.PolicyId)
                }
            }

            $SafePartition = ConvertTo-CIPPODataFilterValue -Value $Partition -Type String
            $Table = Get-CippTable -tablename 'CippReportingDB'
            foreach ($Type in $PolicyIdsByType.Keys) {
                $PolicyIds = $PolicyIdsByType[$Type]
                $Ranges = [System.Collections.Generic.List[string[]]]::new()
                if ($PolicyIds.Count -le $PerPolicyReadLimit) {
                    foreach ($PolicyId in $PolicyIds) { $Ranges.Add(@("$($Type)_$PolicyId-", "$($Type)_$PolicyId.")) }
                } else {
                    $Ranges.Add(@("$($Type)_", "$($Type)``"))
                }
                foreach ($Range in $Ranges) {
                    $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{2}'" -f $SafePartition, (ConvertTo-CIPPODataFilterValue -Value $Range[0] -Type String), (ConvertTo-CIPPODataFilterValue -Value $Range[1] -Type String)
                    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property @('PartitionKey', 'RowKey'))) {
                        $Rest = "$($Row.RowKey)".Substring($Type.Length + 1)
                        if ($Rest.Length -lt 38 -or $Rest[36] -ne '-') { continue }
                        $PolicyId = $Rest.Substring(0, 36)
                        if (-not $PolicyIds.Contains($PolicyId)) { continue }
                        $Devices = $DevicesByPolicy[$PolicyId]
                        if ($null -eq $Devices) {
                            $Devices = @{
                                Ids         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                                NamesWithId = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                                NamesOnly   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                            }
                            $DevicesByPolicy[$PolicyId] = $Devices
                        }
                        $ItemKey = $Rest.Substring(37) -replace '-part\d+$'
                        if ($ItemKey -eq 'Count') { continue }
                        if ($Type -eq $CatalogDevicesType) {
                            # Keyed "<device id>|<device name>|<user>"; a device name may itself hold '|'
                            $First = $ItemKey.IndexOf('|')
                            $Last = $ItemKey.LastIndexOf('|')
                            if ($First -lt 0 -or $Last -le $First) { continue }
                            $DeviceId = $ItemKey.Substring(0, $First)
                            $DeviceName = $ItemKey.Substring($First + 1, $Last - $First - 1)
                            if ($DeviceId) {
                                $null = $Devices.Ids.Add($DeviceId)
                                if ($DeviceName) { $null = $Devices.NamesWithId.Add($DeviceName) }
                            } elseif ($DeviceName) {
                                $null = $Devices.NamesOnly.Add($DeviceName)
                            }
                        } else {
                            # deviceStatuses ids end in "_<device id>"
                            $DeviceId = $ItemKey.Substring($ItemKey.LastIndexOf('_') + 1)
                            if ($DeviceId) { $null = $Devices.Ids.Add($DeviceId) }
                        }
                    }
                }
            }
        } catch {
            $DevicesByPolicy = @{}
            Write-LogMessage -API 'IntuneSettingSearch' -tenant $TenantFilter -message "Failed to count devices for Intune setting search: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
        }

        $Results = foreach ($Group in $Kept) {
            $Policies = @($Group.Policies.Values)
            $PolicyNames = [string[]]@(foreach ($Policy in $Policies) { $Policy.PolicyName })
            [Array]::Sort([Array]$PolicyNames, [Array]$Policies, [System.Collections.IComparer][System.StringComparer]::CurrentCultureIgnoreCase)

            $PolicyTypes = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::CurrentCultureIgnoreCase)
            $RowIds = $null
            $RowNamesWithId = $null
            $RowNamesOnly = $null
            $PolicyRows = foreach ($Policy in $Policies) {
                if ($Policy.PolicyTypeName) { $null = $PolicyTypes.Add($Policy.PolicyTypeName) }
                $Devices = $DevicesByPolicy[$Policy.PolicyId]
                $DeviceCount = $null
                if ($null -ne $Devices) {
                    # A row with only a device name is the same device as a row with an id and that name
                    $Unmatched = [System.Collections.Generic.HashSet[string]]::new($Devices.NamesOnly, [System.StringComparer]::OrdinalIgnoreCase)
                    $Unmatched.ExceptWith($Devices.NamesWithId)
                    $DeviceCount = $Devices.Ids.Count + $Unmatched.Count
                    if ($null -eq $RowIds) {
                        $RowIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $RowNamesWithId = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $RowNamesOnly = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    }
                    $RowIds.UnionWith($Devices.Ids)
                    $RowNamesWithId.UnionWith($Devices.NamesWithId)
                    $RowNamesOnly.UnionWith($Devices.NamesOnly)
                }
                [PSCustomObject]@{
                    Tenant         = $TenantFilter
                    PolicyId       = $Policy.PolicyId
                    PolicyName     = $Policy.PolicyName
                    PolicyTypeName = $Policy.PolicyTypeName
                    URLName        = $Policy.URLName
                    Value          = $Policy.Value
                    DeviceCount    = $DeviceCount
                }
            }

            $RowDeviceCount = $null
            if ($null -ne $RowIds) {
                $RowNamesOnly.ExceptWith($RowNamesWithId)
                $RowDeviceCount = $RowIds.Count + $RowNamesOnly.Count
            }
            [PSCustomObject]@{
                SettingId   = $Group.SettingId
                SettingName = $Group.SettingName
                Category    = $Group.Category
                PolicyTypes = $PolicyTypes -join ', '
                PolicyCount = $Policies.Count
                DeviceCount = $RowDeviceCount
                Policies    = @($PolicyRows)
            }
        }

        $Body = @{
            Results  = @($Results)
            Metadata = @{ Truncated = $Truncated }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -API 'IntuneSettingSearch' -tenant $TenantFilter -message "Failed to search Intune settings: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = Get-NormalizedError -Message $_.Exception.Message }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
