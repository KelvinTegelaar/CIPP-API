function Get-CIPPAssignmentFilterReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    if ($TenantFilter -eq 'AllTenants') {
        $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneAssignmentFilters' -ByTenant

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in @($ItemsByTenant.Keys)) {
            # Hand each tenant its rows and drop them here so they can be freed once processed
            $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
            try {
                $TenantResults = Get-CIPPAssignmentFilterReport -TenantFilter $Tenant -DbItems @{ IntuneAssignmentFilters = $TenantItems }
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'AssignmentFilterReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = $(if ($DbItems) { $DbItems['IntuneAssignmentFilters'] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAssignmentFilters' }) | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $Items) {
        throw "No assignment filter data found for $TenantFilter. Run a cache sync first."
    }

    $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Item in $Items) {
        $Filter = try { $Item.Data | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { continue }
        if ($null -eq $Filter) { continue }

        $Filter | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
        $Results.Add($Filter)
    }

    return $Results
}
