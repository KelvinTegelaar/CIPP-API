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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter

    try {
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
                url    = '/deviceAppManagement/managedAppPolicies?$expand=assignments&$orderby=displayName'
            }
            @{
                id     = 'MobileAppConfigurations'
                method = 'GET'
                url    = '/deviceAppManagement/mobileAppConfigurations?$expand=assignments&$orderby=displayName'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

        # Extract groups for resolving assignment names
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value

        $GraphRequest = [System.Collections.Generic.List[object]]::new()

        # Process Managed App Policies - these need separate assignment lookups
        $ManagedAppPolicies = ($BulkResults | Where-Object { $_.id -eq 'ManagedAppPolicies' }).body.value
        if ($ManagedAppPolicies) {
            # Build bulk requests for assignments of policies that support them
            $AssignmentRequests = [System.Collections.Generic.List[object]]::new()
            foreach ($Policy in $ManagedAppPolicies) {
                # Only certain policy types support assignments endpoint
                $odataType = $Policy.'@odata.type'
                if ($odataType -match 'androidManagedAppProtection|iosManagedAppProtection|windowsManagedAppProtection|targetedManagedAppConfiguration') {
                    $urlSegment = switch -Wildcard ($odataType) {
                        '*androidManagedAppProtection*' { 'androidManagedAppProtections' }
                        '*iosManagedAppProtection*' { 'iosManagedAppProtections' }
                        '*windowsManagedAppProtection*' { 'windowsManagedAppProtections' }
                        '*targetedManagedAppConfiguration*' { 'targetedManagedAppConfigurations' }
                    }
                    if ($urlSegment) {
                        $AssignmentRequests.Add(@{
                                id     = $Policy.id
                                method = 'GET'
                                url    = "/deviceAppManagement/$urlSegment('$($Policy.id)')/assignments"
                            })
                    }
                }
            }

            # Fetch assignments in bulk if we have any
            $AssignmentResults = @{}
            if ($AssignmentRequests.Count -gt 0) {
                $AssignmentBulkResults = New-GraphBulkRequest -Requests $AssignmentRequests -tenantid $TenantFilter
                foreach ($result in $AssignmentBulkResults) {
                    if ($result.body.value) {
                        $AssignmentResults[$result.id] = $result.body.value
                    }
                }
            }

            foreach ($Policy in $ManagedAppPolicies) {
                $policyType = switch -Wildcard ($Policy.'@odata.type') {
                    '*androidManagedAppProtection*' { 'Android App Protection' }
                    '*iosManagedAppProtection*' { 'iOS App Protection' }
                    '*windowsManagedAppProtection*' { 'Windows App Protection' }
                    '*mdmWindowsInformationProtectionPolicy*' { 'Windows Information Protection (MDM)' }
                    '*windowsInformationProtectionPolicy*' { 'Windows Information Protection' }
                    '*targetedManagedAppConfiguration*' { 'App Configuration (MAM)' }
                    '*defaultManagedAppProtection*' { 'Default App Protection' }
                    default { 'App Protection Policy' }
                }

                # Process assignments
                $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
                $PolicyExclude = [System.Collections.Generic.List[string]]::new()
                $Assignments = $AssignmentResults[$Policy.id]
                if ($Assignments) {
                    foreach ($Assignment in $Assignments) {
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
                $Policy | Add-Member -NotePropertyName 'URLName' -NotePropertyValue 'managedAppPolicies' -Force
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

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
