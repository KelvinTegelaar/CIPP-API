function Invoke-ListIntuneScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter

    if ($TenantFilter -eq 'AllTenants') {
        # AllTenants functionality
        $Table = Get-CIPPTable -TableName 'cacheIntuneScripts'
        $PartitionKey = 'IntuneScript'
        $Filter = "PartitionKey eq '$PartitionKey'"
        $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
        $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
        $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
        if ($RunningQueue) {
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                QueueId      = $RunningQueue.RowKey
            }
        } elseif (!$Rows -and !$RunningQueue) {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name 'Intune Scripts - All Tenants' -Link '/endpoint/MEM/list-scripts?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                QueueId      = $Queue.RowKey
            }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'IntuneScriptOrchestrator'
                QueueFunction    = @{
                    FunctionName = 'GetTenants'
                    QueueId      = $Queue.RowKey
                    TenantParams = @{
                        IncludeErrors = $true
                    }
                    DurableName  = 'ListIntuneScriptAllTenants'
                }
                SkipLog          = $true
            }
            Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
        } else {
            $Metadata = [PSCustomObject]@{
                QueueId = $RunningQueue.RowKey ?? $null
            }
            $Results = foreach ($policy in $Rows) {
                ($policy.Policy | ConvertFrom-Json)
            }
        }
    } else {
        $Results = [System.Collections.Generic.List[System.Object]]::new()

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

        try {
            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Host "Failed to retrieve scripts. Error: $($ErrorMessage.NormalizedError)"
        }

        # Extract groups for resolving assignment names
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value

        foreach ($scriptId in @('Windows', 'MacOS', 'Remediation', 'Linux')) {
            $BulkResult = ($BulkResults | Where-Object { $_.id -eq $scriptId })
            if ($BulkResult.status -ne 200) {
                $Results.Add(@{
                        'scriptType'  = $scriptId
                        'displayName' = if (Test-Json $BulkResult.body.error.message) {
                            ($BulkResult.body.error.message | ConvertFrom-Json).Message
                        } else {
                            $BulkResult.body.error.message
                        }
                    })
                continue
            }
            $scripts = $BulkResult.body.value

            if ($scriptId -eq 'Linux') {
                $scripts = $scripts | Where-Object { $_.platforms -eq 'linux' -and $_.templateReference.templateFamily -eq 'deviceConfigurationScripts' }
                $scripts | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name displayName -Value $_.name -Force }
            }

            # Process assignments for each script
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

                $script | Add-Member -NotePropertyName 'ScriptAssignment' -NotePropertyValue ($ScriptAssignment -join ', ') -Force
                $script | Add-Member -NotePropertyName 'ScriptExclude' -NotePropertyValue ($ScriptExclude -join ', ') -Force
            }

            $scripts | Add-Member -MemberType NoteProperty -Name scriptType -Value $scriptId
            Write-Host "$scriptId scripts count: $($scripts.Count)"
            $Results.AddRange(@($scripts))
        }
    }

    $Body = [PSCustomObject]@{
        Results  = @($Results | Where-Object -Property id -NE $null)
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
