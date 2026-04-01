function Push-ListAssignmentFiltersAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheAssignmentFilters'

    try {
        $AssignmentFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $DomainName
        if (-not $AssignmentFilters) { $AssignmentFilters = @() }

        foreach ($filter in @($AssignmentFilters)) {
            if (-not $filter) { continue }

            $GUID = (New-Guid).Guid
            $PolicyData = @{
                id                             = $filter.id
                displayName                    = $filter.displayName
                description                    = $filter.description
                Tenant                         = $DomainName
                platform                       = $filter.platform
                rule                           = $filter.rule
                assignmentFilterManagementType = $filter.assignmentFilterManagementType
                createdDateTime                = $(if (![string]::IsNullOrEmpty($filter.createdDateTime)) { $filter.createdDateTime } else { '' })
                lastModifiedDateTime           = $(if (![string]::IsNullOrEmpty($filter.lastModifiedDateTime)) { $filter.lastModifiedDateTime } else { '' })
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'AssignmentFilter'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant               = $DomainName
            displayName          = "Could not connect to Tenant: $($_.Exception.Message)"
            description          = 'Error'
            lastModifiedDateTime = (Get-Date).ToString('s')
            id                   = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'AssignmentFilter'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
