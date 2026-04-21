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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    $TenantFilter = $Request.Query.tenantFilter
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


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })

}
