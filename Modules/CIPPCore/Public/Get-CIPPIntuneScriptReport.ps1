function Get-CIPPIntuneScriptReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    $ScriptTypeMap = [ordered]@{
        IntuneWindowsScripts     = 'Windows'
        IntuneMacOSScripts       = 'MacOS'
        IntuneRemediationScripts = 'Remediation'
        IntuneLinuxScripts       = 'Linux'
    }

    if ($TenantFilter -eq 'AllTenants') {
        $ByType = @{}
        foreach ($Type in $ScriptTypeMap.Keys) { $ByType[$Type] = Get-CIPPDbItem -TenantFilter 'allTenants' -Type $Type -ByTenant }
        $Tenants = @(foreach ($Type in $ScriptTypeMap.Keys) { $ByType[$Type].Keys }) | Select-Object -Unique

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            # Hand each tenant its rows and drop them here so they can be freed once processed
            $TenantItems = @{}
            foreach ($Type in $ScriptTypeMap.Keys) { $TenantItems[$Type] = $ByType[$Type][$Tenant] ?? @(); $ByType[$Type].Remove($Tenant) }
            try {
                $TenantResults = Get-CIPPIntuneScriptReport -TenantFilter $Tenant -DbItems $TenantItems
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntuneScriptReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneScriptGroups' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $GroupItems) {
        $GroupItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_.RowKey -notlike '*-Count' }
    }
    $Groups = foreach ($GroupItem in $GroupItems) {
        try { $GroupItem.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { $null }
    }

    $ItemsByType = @{}
    $AllItems = [System.Collections.Generic.List[object]]::new()
    foreach ($Type in $ScriptTypeMap.Keys) {
        $Items = @($(if ($DbItems) { $DbItems[$Type] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type }) | Where-Object { $_.RowKey -notlike '*-Count' })
        $ItemsByType[$Type] = $Items
        foreach ($Item in $Items) { $AllItems.Add($Item) }
    }

    if ($AllItems.Count -eq 0) {
        throw "No Intune script data found for $TenantFilter. Run a cache sync first."
    }

    $CacheTimestamp = ($AllItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($TypeKey in $ScriptTypeMap.Keys) {
        $scriptId = $ScriptTypeMap[$TypeKey]
        foreach ($Item in $ItemsByType[$TypeKey]) {
            $script = try { $Item.Data | ConvertFrom-Json -Depth 30 -ErrorAction Stop } catch { continue }
            if ($null -eq $script) { continue }

            if ($scriptId -eq 'Linux') {
                if ($script.platforms -ne 'linux' -or $script.templateReference.templateFamily -ne 'deviceConfigurationScripts') { continue }
                $script | Add-Member -MemberType NoteProperty -Name displayName -Value $script.name -Force
            }

            $ScriptAssignment = [System.Collections.Generic.List[string]]::new()
            $ScriptExclude = [System.Collections.Generic.List[string]]::new()

            if ($script.assignments) {
                foreach ($Assignment in $script.assignments) {
                    $target = $Assignment.target
                    switch ($target.'@odata.type') {
                        '#microsoft.graph.allDevicesAssignmentTarget' { $ScriptAssignment.Add('All Devices') }
                        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $ScriptAssignment.Add('All Licensed Users') }
                        '#microsoft.graph.groupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $ScriptAssignment.Add($groupName) }
                        }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' {
                            $groupName = ($Groups | Where-Object { $_.id -eq $target.groupId }).displayName
                            if ($groupName) { $ScriptExclude.Add($groupName) }
                        }
                    }
                }
            }

            $script | Add-Member -NotePropertyMembers ([ordered]@{
                    ScriptAssignment = ($ScriptAssignment -join ', ')
                    ScriptExclude    = ($ScriptExclude -join ', ')
                    scriptType       = $scriptId
                    CacheTimestamp   = $CacheTimestamp
                }) -Force
            $Results.Add($script)
        }
    }

    return $Results
}
