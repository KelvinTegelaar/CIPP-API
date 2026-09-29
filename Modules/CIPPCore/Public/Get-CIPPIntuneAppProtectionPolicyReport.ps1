function Get-CIPPIntuneAppProtectionPolicyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    $PolicyTypes = @('IntuneAppProtectionManagedAppPolicies', 'IntuneAppProtectionMobileAppConfigurations')

    if ($TenantFilter -eq 'AllTenants') {
        $ByType = @{}
        foreach ($Type in $PolicyTypes) { $ByType[$Type] = Get-CIPPDbItem -TenantFilter 'allTenants' -Type $Type -ByTenant }
        $Tenants = @(foreach ($Type in $PolicyTypes) { $ByType[$Type].Keys }) | Select-Object -Unique

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            # Hand each tenant its rows and drop them here so they can be freed once processed
            $TenantItems = @{}
            foreach ($Type in $PolicyTypes) { $TenantItems[$Type] = $ByType[$Type][$Tenant] ?? @(); $ByType[$Type].Remove($Tenant) }
            try {
                $TenantResults = Get-CIPPIntuneAppProtectionPolicyReport -TenantFilter $Tenant -DbItems $TenantItems
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntuneAppProtectionPolicyReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAppProtectionPolicyGroups' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $GroupItems) {
        $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_.RowKey -notlike '*-Count' }
    }
    $Groups = foreach ($GroupItem in $GroupItems) {
        try { $GroupItem.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { $null }
    }

    $ItemsByType = @{}
    $AllItems = [System.Collections.Generic.List[object]]::new()
    foreach ($Type in $PolicyTypes) {
        $Items = @($(if ($DbItems) { $DbItems[$Type] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type }) | Where-Object { $_.RowKey -notlike '*-Count' })
        $ItemsByType[$Type] = $Items
        foreach ($Item in $Items) { $AllItems.Add($Item) }
    }

    if ($AllItems.Count -eq 0) {
        throw "No app protection policy data found for $TenantFilter. Run a cache sync first."
    }

    $CacheTimestamp = ($AllItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Item in $ItemsByType['IntuneAppProtectionManagedAppPolicies']) {
        $Policy = try { $Item.Data | ConvertFrom-Json -Depth 30 -ErrorAction Stop } catch { continue }
        if ($null -eq $Policy) { continue }

        $policyType = switch ($Policy.URLName) {
            'androidManagedAppProtection' { 'Android App Protection'; break }
            'iosManagedAppProtection' { 'iOS App Protection'; break }
            'windowsManagedAppProtection' { 'Windows App Protection'; break }
            'mdmWindowsInformationProtectionPolicy' { 'Windows Information Protection (MDM)'; break }
            'windowsInformationProtectionPolicy' { 'Windows Information Protection'; break }
            'targetedManagedAppConfiguration' { 'App Configuration (MAM)'; break }
            'defaultManagedAppProtection' { 'Default App Protection'; break }
            default { 'App Protection Policy' }
        }

        $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
        $PolicyExclude = [System.Collections.Generic.List[string]]::new()
        if ($Policy.assignments) {
            foreach ($Assignment in $Policy.assignments) {
                $target = $Assignment.target
                switch ($target.'@odata.type') {
                    '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                    '#microsoft.graph.allLicensedUsersAssignmentTarget' { $PolicyAssignment.Add('All Licensed Users') }
                    '#microsoft.graph.groupAssignmentTarget' {
                        $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                        if ($groupName) { $PolicyAssignment.Add($groupName) }
                    }
                    '#microsoft.graph.exclusionGroupAssignmentTarget' {
                        $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                        if ($groupName) { $PolicyExclude.Add($groupName) }
                    }
                }
            }
        }

        $Policy | Add-Member -NotePropertyMembers ([ordered]@{
                PolicyTypeName   = $policyType
                PolicySource     = 'AppProtection'
                PolicyAssignment = ($PolicyAssignment -join ', ')
                PolicyExclude    = ($PolicyExclude -join ', ')
                CacheTimestamp   = $CacheTimestamp
            }) -Force
        $Results.Add($Policy)
    }

    foreach ($Item in $ItemsByType['IntuneAppProtectionMobileAppConfigurations']) {
        $Config = try { $Item.Data | ConvertFrom-Json -Depth 30 -ErrorAction Stop } catch { continue }
        if ($null -eq $Config) { continue }

        $policyType = switch -Wildcard ($Config.'@odata.type') {
            '*androidManagedStoreAppConfiguration*' { 'Android Enterprise App Configuration' }
            '*androidForWorkAppConfigurationSchema*' { 'Android for Work Configuration' }
            '*iosMobileAppConfiguration*' { 'iOS App Configuration' }
            default { 'App Configuration Policy' }
        }

        $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
        $PolicyExclude = [System.Collections.Generic.List[string]]::new()
        if ($Config.assignments) {
            foreach ($Assignment in $Config.assignments) {
                $target = $Assignment.target
                switch ($target.'@odata.type') {
                    '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                    '#microsoft.graph.allLicensedUsersAssignmentTarget' { $PolicyAssignment.Add('All Licensed Users') }
                    '#microsoft.graph.groupAssignmentTarget' {
                        $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                        if ($groupName) { $PolicyAssignment.Add($groupName) }
                    }
                    '#microsoft.graph.exclusionGroupAssignmentTarget' {
                        $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                        if ($groupName) { $PolicyExclude.Add($groupName) }
                    }
                }
            }
        }

        $ConfigProps = [ordered]@{
            PolicyTypeName   = $policyType
            URLName          = 'mobileAppConfigurations'
            PolicySource     = 'AppConfiguration'
            PolicyAssignment = ($PolicyAssignment -join ', ')
            PolicyExclude    = ($PolicyExclude -join ', ')
        }
        if (-not $Config.PSObject.Properties['isAssigned']) {
            $ConfigProps['isAssigned'] = $false
        }
        $ConfigProps['CacheTimestamp'] = $CacheTimestamp
        $Config | Add-Member -NotePropertyMembers $ConfigProps -Force
        $Results.Add($Config)
    }

    return ($Results | Sort-Object -Property displayName)
}
