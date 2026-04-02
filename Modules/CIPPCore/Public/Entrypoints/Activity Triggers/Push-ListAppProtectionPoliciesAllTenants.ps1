function Push-ListAppProtectionPoliciesAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheAppProtectionPolicies'

    try {
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

        $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $DomainName

        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value

        # Process Managed App Policies
        $ManagedAppPolicies = ($BulkResults | Where-Object { $_.id -eq 'ManagedAppPolicies' }).body.value
        if ($ManagedAppPolicies) {
            $OdataTypes = ($ManagedAppPolicies | Select-Object -ExpandProperty '@odata.type' -Unique) -replace '#microsoft.graph.', ''
            $ManagedAppPoliciesBulkRequests = foreach ($type in $OdataTypes) {
                $urlSegment = switch ($type) {
                    'androidManagedAppProtection' { 'androidManagedAppProtections' }
                    'iosManagedAppProtection' { 'iosManagedAppProtections' }
                    'mdmWindowsInformationProtectionPolicy' { 'mdmWindowsInformationProtectionPolicies' }
                    'windowsManagedAppProtection' { 'windowsManagedAppProtections' }
                    'targetedManagedAppConfiguration' { 'targetedManagedAppConfigurations' }
                    default { $null }
                }
                if ($urlSegment) {
                    @{
                        id     = $type
                        method = 'GET'
                        url    = "/deviceAppManagement/${urlSegment}?`$expand=assignments&`$orderby=displayName"
                    }
                }
            }

            $ManagedAppPoliciesBulkResults = New-GraphBulkRequest -Requests @($ManagedAppPoliciesBulkRequests) -tenantid $DomainName
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

                $GUID = (New-Guid).Guid
                $PolicyData = @{
                    id                   = $Policy.id
                    displayName          = $Policy.displayName
                    Tenant               = $DomainName
                    lastModifiedDateTime = $(if (![string]::IsNullOrEmpty($Policy.lastModifiedDateTime)) { $Policy.lastModifiedDateTime } else { '' })
                    PolicyTypeName       = $policyType
                    URLName              = $Policy.URLName
                    PolicySource         = 'AppProtection'
                    PolicyAssignment     = ($PolicyAssignment -join ', ')
                    PolicyExclude        = ($PolicyExclude -join ', ')
                }
                $Entity = @{
                    Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                    RowKey       = [string]$GUID
                    PartitionKey = 'AppProtectionPolicy'
                    Tenant       = [string]$DomainName
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
            }
        }

        # Process Mobile App Configurations
        $MobileAppConfigs = ($BulkResults | Where-Object { $_.id -eq 'MobileAppConfigurations' }).body.value
        if ($MobileAppConfigs) {
            foreach ($Config in $MobileAppConfigs) {
                $policyType = switch -Wildcard ($Config.'@odata.type') {
                    '*androidManagedStoreAppConfiguration*' { 'Android Enterprise App Configuration' }
                    '*androidForWorkAppConfigurationSchema*' { 'Android for Work Configuration' }
                    '*iosMobileAppConfiguration*' { 'iOS App Configuration' }
                    default { 'App Configuration Policy' }
                }

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

                $GUID = (New-Guid).Guid
                $PolicyData = @{
                    id                   = $Config.id
                    displayName          = $Config.displayName
                    Tenant               = $DomainName
                    lastModifiedDateTime = $(if (![string]::IsNullOrEmpty($Config.lastModifiedDateTime)) { $Config.lastModifiedDateTime } else { '' })
                    PolicyTypeName       = $policyType
                    URLName              = 'mobileAppConfigurations'
                    PolicySource         = 'AppConfiguration'
                    PolicyAssignment     = ($PolicyAssignment -join ', ')
                    PolicyExclude        = ($PolicyExclude -join ', ')
                }
                $Entity = @{
                    Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                    RowKey       = [string]$GUID
                    PartitionKey = 'AppProtectionPolicy'
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
            PolicyTypeName       = 'Error'
            lastModifiedDateTime = (Get-Date).ToString('s')
            id                   = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'AppProtectionPolicy'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
