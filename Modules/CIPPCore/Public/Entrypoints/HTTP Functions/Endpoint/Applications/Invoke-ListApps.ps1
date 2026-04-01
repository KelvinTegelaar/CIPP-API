function Invoke-ListApps {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        if ($TenantFilter -eq 'AllTenants') {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName 'cacheApps'
            $PartitionKey = 'App'
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
                $Queue = New-CippQueueEntry -Name 'Applications - All Tenants' -Link '/endpoint/applications/list?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'AppsOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListAppsAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $GraphRequest = foreach ($policy in $Rows) {
                    ($policy.Policy | ConvertFrom-Json)
                }
            }
        } else {
            # Use bulk requests to get groups and apps with assignments
            $BulkRequests = @(
                @{
                    id     = 'Groups'
                    method = 'GET'
                    url    = '/groups?$top=999&$select=id,displayName'
                }
                @{
                    id     = 'Apps'
                    method = 'GET'
                    url    = "/deviceAppManagement/mobileApps?`$top=999&`$expand=assignments&`$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName"
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

            # Extract groups for resolving assignment names
            $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
            $Apps = ($BulkResults | Where-Object { $_.id -eq 'Apps' }).body.value

            $GraphRequest = foreach ($App in $Apps) {
                # Process assignments
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
                                if ($groupName) { $AppExclude.Add($groupName) }
                            }
                        }
                    }
                }

                $App | Add-Member -NotePropertyName 'AppAssignment' -NotePropertyValue ($AppAssignment -join ', ') -Force
                $App | Add-Member -NotePropertyName 'AppExclude' -NotePropertyValue ($AppExclude -join ', ') -Force
                $App
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    $Body = [PSCustomObject]@{
        Results  = @($GraphRequest | Where-Object -Property id -NE $null)
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
