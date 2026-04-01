function Invoke-ListCompliancePolicies {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName 'cacheCompliancePolicies'
            $PartitionKey = 'CompliancePolicy'
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
                $Queue = New-CippQueueEntry -Name 'Compliance Policies - All Tenants' -Link '/endpoint/MEM/list-compliance-policies?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'CompliancePolicyOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListCompliancePoliciesAllTenants'
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
            # Use bulk requests to get groups and compliance policies
            $BulkRequests = @(
                @{
                    id     = 'Groups'
                    method = 'GET'
                    url    = '/groups?$top=999&$select=id,displayName'
                }
                @{
                    id     = 'CompliancePolicies'
                    method = 'GET'
                    url    = '/deviceManagement/deviceCompliancePolicies?$expand=assignments&$orderby=displayName'
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

            # Extract results
            $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
            $Policies = ($BulkResults | Where-Object { $_.id -eq 'CompliancePolicies' }).body.value

            $GraphRequest = [System.Collections.Generic.List[object]]::new()

            foreach ($Policy in $Policies) {
                # Determine policy type from @odata.type
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

                # Process assignments
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

                $GraphRequest.Add($Policy)
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
