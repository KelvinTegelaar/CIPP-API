function Get-CIPPIntuneScriptReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $ScriptTypeMap = [ordered]@{
        IntuneWindowsScripts     = 'Windows'
        IntuneMacOSScripts       = 'MacOS'
        IntuneRemediationScripts = 'Remediation'
        IntuneLinuxScripts       = 'Linux'
    }

    if ($TenantFilter -eq 'AllTenants') {
        $Tenants = foreach ($Type in $ScriptTypeMap.Keys) {
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
                $TenantResults = Get-CIPPIntuneScriptReport -TenantFilter $Tenant
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
        $Items = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type | Where-Object { $_.RowKey -notlike '*-Count' })
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

            $script | Add-Member -NotePropertyName 'ScriptAssignment' -NotePropertyValue ($ScriptAssignment -join ', ') -Force
            $script | Add-Member -NotePropertyName 'ScriptExclude' -NotePropertyValue ($ScriptExclude -join ', ') -Force
            $script | Add-Member -MemberType NoteProperty -Name scriptType -Value $scriptId -Force
            $script | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            $Results.Add($script)
        }
    }

    return $Results
}
