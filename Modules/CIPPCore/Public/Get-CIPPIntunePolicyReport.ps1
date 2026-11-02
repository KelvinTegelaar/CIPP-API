function Get-CIPPIntunePolicyReport {
    <#
    .SYNOPSIS
        Returns the Intune configuration policy list from the CIPP reporting database

    .DESCRIPTION
        Retrieves every policy family defined by Get-CIPPIntunePolicyListDefinitions,
        then applies the same normalization used by the live ListIntunePolicy endpoint.

    .PARAMETER TenantFilter
        Tenant domain name or 'AllTenants'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $PolicyDefinitions = @(Get-CIPPIntunePolicyListDefinitions)
    $IsAllTenants = $TenantFilter -eq 'AllTenants'
    if ($IsAllTenants) {
        # Cross-partition cache scans can retain rows for tenants no longer in scope.
        $TenantList = Get-Tenants -IncludeErrors
        $ValidTenants = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@($TenantList.defaultDomainName),
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $DbTenantFilter = 'allTenants'
    } else {
        $DbTenantFilter = $TenantFilter
    }

    try {
        # Prefer the group snapshot collected with IntunePolicies so assignment
        # names match live immediately after a policy sync. Read the normal Groups
        # cache only for tenants that do not have an Intune policy group snapshot.
        $GroupLookupByTenant = @{}
        $SnapshotTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $IntuneGroupItems = @(Get-CIPPDbItem -TenantFilter $DbTenantFilter -Type 'IntunePolicyGroups')
        foreach ($GroupItem in $IntuneGroupItems) {
            if ($IsAllTenants -and -not $ValidTenants.Contains($GroupItem.PartitionKey)) { continue }

            $GroupTenant = if ($IsAllTenants) { $GroupItem.PartitionKey } else { $TenantFilter }
            [void]$SnapshotTenants.Add($GroupTenant)
            # A count row also marks a completed, authoritative empty snapshot.
            if ($GroupItem.RowKey -like '*-Count') { continue }

            $GroupObj = try { $GroupItem.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
            if (-not $GroupObj.id) { continue }
            if (-not $GroupLookupByTenant.ContainsKey($GroupTenant)) {
                $GroupLookupByTenant[$GroupTenant] = @{}
            }
            $GroupLookupByTenant[$GroupTenant][$GroupObj.id] = $GroupObj.displayName
        }

        $FallbackTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($IsAllTenants) {
            foreach ($Tenant in $ValidTenants) {
                if (-not $SnapshotTenants.Contains($Tenant)) { [void]$FallbackTenants.Add($Tenant) }
            }
        } elseif (-not $SnapshotTenants.Contains($TenantFilter)) {
            [void]$FallbackTenants.Add($TenantFilter)
        }

        if ($FallbackTenants.Count -gt 0) {
            # One cross-partition fallback read is cheaper than one query per missing tenant.
            $GroupItems = @(Get-CIPPDbItem -TenantFilter $DbTenantFilter -Type 'Groups')
            foreach ($GroupItem in $GroupItems) {
                if ($GroupItem.RowKey -like '*-Count') { continue }

                $GroupTenant = if ($IsAllTenants) { $GroupItem.PartitionKey } else { $TenantFilter }
                if (-not $FallbackTenants.Contains($GroupTenant)) { continue }

                $GroupObj = try { $GroupItem.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                if (-not $GroupObj.id) { continue }
                if (-not $GroupLookupByTenant.ContainsKey($GroupTenant)) {
                    $GroupLookupByTenant[$GroupTenant] = @{}
                }
                $GroupLookupByTenant[$GroupTenant][$GroupObj.id] = $GroupObj.displayName
            }
        }

        $CachedFamilies = [System.Collections.Generic.List[object]]::new()
        $CacheTimestamp = $null
        # Collect families first so every returned row receives the same latest timestamp.
        foreach ($Definition in $PolicyDefinitions) {
            $Items = @(Get-CIPPDbItem -TenantFilter $DbTenantFilter -Type $Definition.CacheType |
                    Where-Object { $_.RowKey -notlike '*-Count' })

            if (-not $Items) { continue }
            $CachedFamilies.Add([PSCustomObject]@{
                    Definition = $Definition
                    Items      = $Items
                })

            if (-not $IsAllTenants) {
                $TypeTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
                if ($null -eq $CacheTimestamp -or ($TypeTimestamp -and $TypeTimestamp -gt $CacheTimestamp)) {
                    $CacheTimestamp = $TypeTimestamp
                }
            }
        }

        $AllPolicies = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Family in $CachedFamilies) {
            foreach ($Item in $Family.Items) {
                if ($IsAllTenants -and -not $ValidTenants.Contains($Item.PartitionKey)) { continue }

                # Keep assignment lookups isolated by tenant during AllTenants reports.
                $PolicyTenant = if ($IsAllTenants) { $Item.PartitionKey } else { $TenantFilter }
                try {
                    $Policy = $Item.Data | ConvertFrom-Json -Depth 25 -ErrorAction Stop
                } catch {
                    Write-LogMessage -API 'IntunePolicyReport' -tenant $PolicyTenant -message "Failed to parse cached Intune policy item '$($Item.RowKey)' from '$($Family.Definition.CacheType)': $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
                    continue
                }
                if ($null -eq $Policy) { continue }

                $GroupLookup = if ($GroupLookupByTenant.ContainsKey($PolicyTenant)) {
                    $GroupLookupByTenant[$PolicyTenant]
                } else {
                    @{}
                }

                $NormalizedPolicy = ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName $Family.Definition.Id -DefaultPolicyTypeName $Family.Definition.PolicyTypeName -GroupLookup $GroupLookup
                if ($null -eq $NormalizedPolicy) { continue }

                if ($IsAllTenants) {
                    $NormalizedPolicy | Add-Member -NotePropertyName Tenant -NotePropertyValue $Item.PartitionKey -Force
                } else {
                    $NormalizedPolicy | Add-Member -NotePropertyName CacheTimestamp -NotePropertyValue $CacheTimestamp -Force
                }
                $AllPolicies.Add($NormalizedPolicy)
            }
        }

        return ($AllPolicies | Sort-Object -Property displayName)
    } catch {
        Write-LogMessage -API 'IntunePolicyReport' -tenant $TenantFilter -message "Failed to generate Intune policy report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
