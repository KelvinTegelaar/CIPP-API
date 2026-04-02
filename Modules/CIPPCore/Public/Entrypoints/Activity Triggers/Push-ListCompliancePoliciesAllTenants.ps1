function Push-ListCompliancePoliciesAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheCompliancePolicies'

    try {
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

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $DomainName

        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
        $Policies = ($BulkResults | Where-Object { $_.id -eq 'CompliancePolicies' }).body.value

        foreach ($Policy in $Policies) {
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
                description          = $Policy.description
                PolicyTypeName       = $policyType
                PolicyAssignment     = ($PolicyAssignment -join ', ')
                PolicyExclude        = ($PolicyExclude -join ', ')
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'CompliancePolicy'
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
            PartitionKey = 'CompliancePolicy'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
