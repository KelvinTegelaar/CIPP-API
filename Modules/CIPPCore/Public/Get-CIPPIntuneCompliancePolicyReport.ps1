function Get-CIPPIntuneCompliancePolicyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneDeviceCompliancePolicies'
        $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPIntuneCompliancePolicyReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntuneCompliancePolicyReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceCompliancePolicies' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $Items) {
        throw "No compliance policy data found for $TenantFilter. Run a cache sync first."
    }

    $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneCompliancePolicyGroups' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $GroupItems) {
        $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_.RowKey -notlike '*-Count' }
    }
    $Groups = foreach ($GroupItem in $GroupItems) {
        try { $GroupItem.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { $null }
    }

    $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Item in $Items) {
        $Policy = try { $Item.Data | ConvertFrom-Json -Depth 30 -ErrorAction Stop } catch { continue }
        if ($null -eq $Policy) { continue }

        $policyType = switch -Wildcard ($Policy.'@odata.type') {
            '*windows10CompliancePolicy*' { 'Windows 10/11 Compliance' }
            '*windowsPhone81CompliancePolicy*' { 'Windows Phone 8.1 Compliance' }
            '*windows81CompliancePolicy*' { 'Windows 8.1 Compliance' }
            '*iosCompliancePolicy*' { 'iOS Compliance' }
            '*macOSCompliancePolicy*' { 'macOS Compliance' }
            '*androidCompliancePolicy*' { 'Android Compliance' }
            '*androidDeviceOwnerCompliancePolicy*' { 'Android Enterprise Compliance' }
            '*androidWorkProfileCompliancePolicy*' { 'Android Work Profile Compliance' }
            '*aospDeviceOwnerCompliancePolicy*' { 'AOSP Compliance' }
            default { 'Compliance Policy' }
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
        $Policy | Add-Member -NotePropertyName 'PolicyAssignment' -NotePropertyValue ($PolicyAssignment -join ', ') -Force
        $Policy | Add-Member -NotePropertyName 'PolicyExclude' -NotePropertyValue ($PolicyExclude -join ', ') -Force
        $Policy | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
        $Results.Add($Policy)
    }

    return ($Results | Sort-Object -Property displayName)
}
