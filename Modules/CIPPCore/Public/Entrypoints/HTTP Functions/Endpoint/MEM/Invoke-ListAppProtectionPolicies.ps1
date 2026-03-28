function Invoke-ListAppProtectionPolicies {
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

    try {
        if ($TenantFilter -eq 'AllTenants') {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName 'cacheAppProtectionPolicies'
            $PartitionKey = 'AppProtectionPolicy'
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
                $Queue = New-CippQueueEntry -Name 'App Protection Policies - All Tenants' -Link '/endpoint/MEM/list-appprotection-policies?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'AppProtectionPolicyOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListAppProtectionPoliciesAllTenants'
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
            # Use bulk requests to get groups, managed app policies and mobile app configurations
            $BulkRequests = @(
                @{
                    id     = 'Groups'
                    method = 'GET'
                    url    = '/groups?$top=999&$select=id,displayName'
                }
                @{
                    id     = 'ManagedAppPolicies'
                    method = 'GET'
                    url    = '/deviceAppManagement/managedAppPolicies?$orderby=displayName'
                }
                @{
                    id     = 'MobileAppConfigurations'
                    method = 'GET'
                    url    = '/deviceAppManagement/mobileAppConfigurations?$expand=assignments&$orderby=displayName'
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter

            # Extract groups for resolving assignment names
            $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value

            $GraphRequest = [System.Collections.Generic.List[object]]::new()

            # Process Managed App Policies - these need separate assignment lookups as the ManagedAppPolicies endpoint does not support $expand
            $ManagedAppPolicies = ($BulkResults | Where-Object { $_.id -eq 'ManagedAppPolicies' }).body.value
            if ($ManagedAppPolicies) {
                # Get all @odata.type and deduplicate them
                $OdataTypes = ($ManagedAppPolicies | Select-Object -ExpandProperty '@odata.type' -Unique) -replace '#microsoft.graph.', ''
                $ManagedAppPoliciesBulkRequests = foreach ($type in $OdataTypes) {
                    # Translate to URL segments
                    $urlSegment = switch ($type) {
                        'androidManagedAppProtection' { 'androidManagedAppProtections' }
                        'iosManagedAppProtection' { 'iosManagedAppProtections' }
                        'mdmWindowsInformationProtectionPolicy' { 'mdmWindowsInformationProtectionPolicies' }
                        'windowsManagedAppProtection' { 'windowsManagedAppProtections' }
                        'targetedManagedAppConfiguration' { 'targetedManagedAppConfigurations' }
                        default { $null }
                    }
                    Write-Information "Type: $type => URL Segment: $urlSegment"
                    if ($urlSegment) {
                        @{
                            id     = $type
                            method = 'GET'
                            url    = "/deviceAppManagement/${urlSegment}?`$expand=assignments&`$orderby=displayName"
                        }
                    }
                }

                $ManagedAppPoliciesBulkResults = New-GraphBulkRequest -Requests @($ManagedAppPoliciesBulkRequests) -tenantid $TenantFilter
                # Do this horriblenes as a workaround, as the results dont return with a odata.type property
                $ManagedAppPolicies = $ManagedAppPoliciesBulkResults | ForEach-Object {
                    $URLName = $_.id
                    $_.body.value | Add-Member -NotePropertyName 'URLName' -NotePropertyValue $URLName -Force
                    $_.body.value
                }



                foreach ($Policy in $ManagedAppPolicies) {
                    $policyType = switch ($Policy.'URLName') {
                        'androidManagedAppProtection' { 'Android App Protection'; break }
                        'iosManagedAppProtection' { 'iOS App Protection'; break }
                        'windowsManagedAppProtection' { 'Windows App Protection'; break }
                        'mdmWindowsInformationProtectionPolicy' { 'Windows Information Protection (MDM)'; break }
                        'windowsInformationProtectionPolicy' { 'Windows Information Protection'; break }
                        'targetedManagedAppConfiguration' { 'App Configuration (MAM)'; break }
                        'defaultManagedAppProtection' { 'Default App Protection'; break }
                        default { 'App Protection Policy' }
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
                    # $Policy | Add-Member -NotePropertyName 'URLName' -NotePropertyValue 'managedAppPolicies' -Force
                    $Policy | Add-Member -NotePropertyName 'PolicySource' -NotePropertyValue 'AppProtection' -Force
                    $Policy | Add-Member -NotePropertyName 'PolicyAssignment' -NotePropertyValue ($PolicyAssignment -join ', ') -Force
                    $Policy | Add-Member -NotePropertyName 'PolicyExclude' -NotePropertyValue ($PolicyExclude -join ', ') -Force
                    $GraphRequest.Add($Policy)
                }
            }

            # Process Mobile App Configurations - assignments are already expanded
            $MobileAppConfigs = ($BulkResults | Where-Object { $_.id -eq 'MobileAppConfigurations' }).body.value
            if ($MobileAppConfigs) {
                foreach ($Config in $MobileAppConfigs) {
                    $policyType = switch -Wildcard ($Config.'@odata.type') {
                        '*androidManagedStoreAppConfiguration*' { 'Android Enterprise App Configuration' }
                        '*androidForWorkAppConfigurationSchema*' { 'Android for Work Configuration' }
                        '*iosMobileAppConfiguration*' { 'iOS App Configuration' }
                        default { 'App Configuration Policy' }
                    }

                    # Process assignments
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

                    # Ensure isAssigned property exists for consistency
                    if (-not $Config.PSObject.Properties['isAssigned']) {
                        $Config | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $false -Force
                    }
                    $GraphRequest.Add($Config)
                }
            }

            # Sort combined results by displayName
            $GraphRequest = $GraphRequest | Sort-Object -Property displayName
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
