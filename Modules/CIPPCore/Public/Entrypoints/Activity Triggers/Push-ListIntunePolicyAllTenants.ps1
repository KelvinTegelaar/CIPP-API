function Push-ListIntunePolicyAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheIntunePolicies'

    try {
        $BulkRequests = [PSCustomObject]@(
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            }
            @{
                id     = 'DeviceConfigurations'
                method = 'GET'
                url    = "/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName,description&`$expand=assignments&`$top=1000"
            }
            @{
                id     = 'WindowsDriverUpdateProfiles'
                method = 'GET'
                url    = "/deviceManagement/windowsDriverUpdateProfiles?`$expand=assignments&`$top=200"
            }
            @{
                id     = 'WindowsFeatureUpdateProfiles'
                method = 'GET'
                url    = "/deviceManagement/windowsFeatureUpdateProfiles?`$expand=assignments&`$top=200"
            }
            @{
                id     = 'windowsQualityUpdatePolicies'
                method = 'GET'
                url    = "/deviceManagement/windowsQualityUpdatePolicies?`$expand=assignments&`$top=200"
            }
            @{
                id     = 'windowsQualityUpdateProfiles'
                method = 'GET'
                url    = "/deviceManagement/windowsQualityUpdateProfiles?`$expand=assignments&`$top=200"
            }
            @{
                id     = 'GroupPolicyConfigurations'
                method = 'GET'
                url    = "/deviceManagement/groupPolicyConfigurations?`$expand=assignments&`$top=1000"
            }
            @{
                id     = 'MobileAppConfigurations'
                method = 'GET'
                url    = "/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
            }
            @{
                id     = 'ConfigurationPolicies'
                method = 'GET'
                url    = "/deviceManagement/configurationPolicies?`$expand=assignments&`$top=1000"
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $DomainName

        # Extract groups for resolving assignment names
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value

        $Policies = $BulkResults | Where-Object { $_.id -ne 'Groups' } | ForEach-Object {
            $URLName = $_.Id
            $_.body.Value | ForEach-Object {
                $policyTypeName = switch -Wildcard ($_.'assignments@odata.context') {
                    '*microsoft.graph.windowsIdentityProtectionConfiguration*' { 'Identity Protection' }
                    '*microsoft.graph.windows10EndpointProtectionConfiguration*' { 'Endpoint Protection' }
                    '*microsoft.graph.windows10CustomConfiguration*' { 'Custom' }
                    '*microsoft.graph.windows10DeviceFirmwareConfigurationInterface*' { 'Firmware Configuration' }
                    '*groupPolicyConfigurations*' { 'Administrative Templates' }
                    '*windowsDomainJoinConfiguration*' { 'Domain Join configuration' }
                    '*windowsUpdateForBusinessConfiguration*' { 'Update Configuration' }
                    '*windowsHealthMonitoringConfiguration*' { 'Health Monitoring' }
                    '*microsoft.graph.macOSGeneralDeviceConfiguration*' { 'MacOS Configuration' }
                    '*microsoft.graph.macOSEndpointProtectionConfiguration*' { 'MacOS Endpoint Protection' }
                    '*microsoft.graph.androidWorkProfileGeneralDeviceConfiguration*' { 'Android Configuration' }
                    '*windowsFeatureUpdateProfiles*' { 'Feature Update' }
                    '*windowsQualityUpdatePolicies*' { 'Quality Update' }
                    '*windowsQualityUpdateProfiles*' { 'Quality Update' }
                    '*iosUpdateConfiguration*' { 'iOS Update Configuration' }
                    '*windowsDriverUpdateProfiles*' { 'Driver Update' }
                    '*configurationPolicies*' { 'Device Configuration' }
                    default { $_.'assignments@odata.context' }
                }
                $Assignments = $_.assignments.target | Select-Object -Property '@odata.type', groupId
                $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
                $PolicyExclude = [System.Collections.Generic.List[string]]::new()
                foreach ($target in $Assignments) {
                    switch ($target.'@odata.type') {
                        '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                        '#microsoft.graph.exclusionallDevicesAssignmentTarget' { $PolicyExclude.Add('All Devices') }
                        '#microsoft.graph.allUsersAssignmentTarget' { $PolicyAssignment.Add('All Users') }
                        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $PolicyAssignment.Add('All Licenced Users') }
                        '#microsoft.graph.exclusionallUsersAssignmentTarget' { $PolicyExclude.Add('All Users') }
                        '#microsoft.graph.groupAssignmentTarget' { $PolicyAssignment.Add($Groups.Where({ $_.id -eq $target.groupId }).displayName) }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' { $PolicyExclude.Add($Groups.Where({ $_.id -eq $target.groupId }).displayName) }
                        default {
                            $PolicyAssignment.Add($null)
                            $PolicyExclude.Add($null)
                        }
                    }
                }
                if ($null -eq $_.displayname) { $_ | Add-Member -NotePropertyName displayName -NotePropertyValue $_.name }
                $_ | Add-Member -NotePropertyName PolicyTypeName -NotePropertyValue $policyTypeName
                $_ | Add-Member -NotePropertyName URLName -NotePropertyValue $URLName
                $_ | Add-Member -NotePropertyName PolicyAssignment -NotePropertyValue ($PolicyAssignment -join ', ')
                $_ | Add-Member -NotePropertyName PolicyExclude -NotePropertyValue ($PolicyExclude -join ', ')
                $_
            } | Where-Object { $null -ne $_.DisplayName }
        }

        # Filter out linux scripts
        $Policies = $Policies | Where-Object { $_.platforms -ne 'linux' -and $_.templateReference.templateFamily -ne 'deviceConfigurationScripts' }

        foreach ($policy in $Policies) {
            $GUID = (New-Guid).Guid
            $PolicyData = @{
                id                   = $policy.id
                displayName          = $policy.displayName
                Tenant               = $DomainName
                lastModifiedDateTime = $(if (![string]::IsNullOrEmpty($policy.lastModifiedDateTime)) { $policy.lastModifiedDateTime } else { '' })
                description          = $policy.description
                PolicyTypeName       = $policy.PolicyTypeName
                URLName              = $policy.URLName
                PolicyAssignment     = $policy.PolicyAssignment
                PolicyExclude        = $policy.PolicyExclude
            }

            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'IntunePolicy'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
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
            PartitionKey = 'IntunePolicy'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
