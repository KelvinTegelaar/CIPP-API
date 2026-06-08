function Get-CIPPIntuneAppProtectionPolicyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $PolicyTypes = @('IntuneAppProtectionManagedAppPolicies', 'IntuneAppProtectionMobileAppConfigurations')

    if ($TenantFilter -eq 'AllTenants') {
        $Tenants = foreach ($Type in $PolicyTypes) {
            Get-CIPPDbItem -TenantFilter 'allTenants' -Type $Type |
                Where-Object { $_.RowKey -notlike '*-Count' } |
                Select-Object -ExpandProperty PartitionKey -Unique
        }
        $Tenants = @($Tenants | Select-Object -Unique)

        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPIntuneAppProtectionPolicyReport -TenantFilter $Tenant
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
        $Items = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type | Where-Object { $_.RowKey -notlike '*-Count' })
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

        $Policy | Add-Member -NotePropertyName 'PolicyTypeName' -NotePropertyValue $policyType -Force
        $Policy | Add-Member -NotePropertyName 'PolicySource' -NotePropertyValue 'AppProtection' -Force
        $Policy | Add-Member -NotePropertyName 'PolicyAssignment' -NotePropertyValue ($PolicyAssignment -join ', ') -Force
        $Policy | Add-Member -NotePropertyName 'PolicyExclude' -NotePropertyValue ($PolicyExclude -join ', ') -Force
        $Policy | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
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

        $Config | Add-Member -NotePropertyName 'PolicyTypeName' -NotePropertyValue $policyType -Force
        $Config | Add-Member -NotePropertyName 'URLName' -NotePropertyValue 'mobileAppConfigurations' -Force
        $Config | Add-Member -NotePropertyName 'PolicySource' -NotePropertyValue 'AppConfiguration' -Force
        $Config | Add-Member -NotePropertyName 'PolicyAssignment' -NotePropertyValue ($PolicyAssignment -join ', ') -Force
        $Config | Add-Member -NotePropertyName 'PolicyExclude' -NotePropertyValue ($PolicyExclude -join ', ') -Force
        if (-not $Config.PSObject.Properties['isAssigned']) {
            $Config | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $false -Force
        }
        $Config | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
        $Results.Add($Config)
    }

    return ($Results | Sort-Object -Property displayName)
}
