function Get-CIPPIntuneApplicationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    if ($TenantFilter -eq 'AllTenants') {
        $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneApplications' -ByTenant

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in @($ItemsByTenant.Keys)) {
            # Hand each tenant its rows and drop them here so they can be freed once processed
            $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
            try {
                $TenantResults = Get-CIPPIntuneApplicationReport -TenantFilter $Tenant -DbItems @{ IntuneApplications = $TenantItems }
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntuneApplicationReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = $(if ($DbItems) { $DbItems['IntuneApplications'] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneApplications' }) | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $Items) {
        throw "No Intune application data found for $TenantFilter. Run a cache sync first."
    }

    $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneApplicationGroups' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $GroupItems) {
        $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_.RowKey -notlike '*-Count' }
    }
    $Groups = foreach ($GroupItem in $GroupItems) {
        try { $GroupItem.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { $null }
    }

    $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Item in $Items) {
        $App = try { $Item.Data | ConvertFrom-Json -Depth 30 -ErrorAction Stop } catch { continue }
        if ($null -eq $App) { continue }

        $AppAssignment = [System.Collections.Generic.List[string]]::new()
        $AppExclude = [System.Collections.Generic.List[string]]::new()

        if ($App.assignments) {
            foreach ($Assignment in $App.assignments) {
                $target = $Assignment.target
                $intent = $Assignment.intent
                $intentSuffix = if ($intent) { " ($intent)" } else { '' }

                switch ($target.'@odata.type') {
                    '#microsoft.graph.allDevicesAssignmentTarget' { $AppAssignment.Add("All Devices$intentSuffix") }
                    '#microsoft.graph.allLicensedUsersAssignmentTarget' { $AppAssignment.Add("All Licensed Users$intentSuffix") }
                    '#microsoft.graph.groupAssignmentTarget' {
                        $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                        if ($groupName) { $AppAssignment.Add("$groupName$intentSuffix") }
                    }
                    '#microsoft.graph.exclusionGroupAssignmentTarget' {
                        $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                        if ($groupName) { $AppExclude.Add("$groupName$intentSuffix") }
                    }
                }
            }
        }

        $App | Add-Member -NotePropertyMembers ([ordered]@{
                AppAssignment  = ($AppAssignment -join ', ')
                AppExclude     = ($AppExclude -join ', ')
                CacheTimestamp = $CacheTimestamp
            }) -Force
        $Results.Add($App)
    }

    return ($Results | Sort-Object -Property displayName)
}
