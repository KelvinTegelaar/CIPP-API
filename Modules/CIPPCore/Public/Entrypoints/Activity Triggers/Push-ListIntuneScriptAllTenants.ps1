function Push-ListIntuneScriptAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheIntuneScripts'

    try {
        $BulkRequests = @(
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            }
            @{
                id     = 'Windows'
                method = 'GET'
                url    = '/deviceManagement/deviceManagementScripts?$expand=assignments'
            }
            @{
                id     = 'MacOS'
                method = 'GET'
                url    = '/deviceManagement/deviceShellScripts?$expand=assignments'
            }
            @{
                id     = 'Remediation'
                method = 'GET'
                url    = '/deviceManagement/deviceHealthScripts?$expand=assignments'
            }
            @{
                id     = 'Linux'
                method = 'GET'
                url    = '/deviceManagement/configurationPolicies?$expand=assignments'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $DomainName

        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value

        foreach ($scriptId in @('Windows', 'MacOS', 'Remediation', 'Linux')) {
            $BulkResult = ($BulkResults | Where-Object { $_.id -eq $scriptId })
            if ($BulkResult.status -ne 200) {
                continue
            }
            $scripts = $BulkResult.body.value

            if ($scriptId -eq 'Linux') {
                $scripts = $scripts | Where-Object { $_.platforms -eq 'linux' -and $_.templateReference.templateFamily -eq 'deviceConfigurationScripts' }
                $scripts | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name displayName -Value $_.name -Force }
            }

            foreach ($script in $scripts) {
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

                $GUID = (New-Guid).Guid
                $PolicyData = @{
                    id                   = $script.id
                    displayName          = $script.displayName
                    Tenant               = $DomainName
                    scriptType           = $scriptId
                    description          = $script.description
                    runAsAccount         = $script.runAsAccount
                    lastModifiedDateTime = $(if (![string]::IsNullOrEmpty($script.lastModifiedDateTime)) { $script.lastModifiedDateTime } else { '' })
                    ScriptAssignment     = ($ScriptAssignment -join ', ')
                    ScriptExclude        = ($ScriptExclude -join ', ')
                }
                $Entity = @{
                    Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                    RowKey       = [string]$GUID
                    PartitionKey = 'IntuneScript'
                    Tenant       = [string]$DomainName
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
            }
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant               = $DomainName
            displayName          = "Could not connect to Tenant: $($_.Exception.Message)"
            scriptType           = 'Error'
            lastModifiedDateTime = (Get-Date).ToString('s')
            id                   = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'IntuneScript'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
