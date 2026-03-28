function Push-ListAppsAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheApps'

    try {
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

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $DomainName

        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
        $Apps = ($BulkResults | Where-Object { $_.id -eq 'Apps' }).body.value

        foreach ($App in $Apps) {
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

            $GUID = (New-Guid).Guid
            $PolicyData = @{
                id                   = $App.id
                displayName          = $App.displayName
                Tenant               = $DomainName
                publishingState      = $App.publishingState
                lastModifiedDateTime = $(if (![string]::IsNullOrEmpty($App.lastModifiedDateTime)) { $App.lastModifiedDateTime } else { '' })
                createdDateTime      = $(if (![string]::IsNullOrEmpty($App.createdDateTime)) { $App.createdDateTime } else { '' })
                AppAssignment        = ($AppAssignment -join ', ')
                AppExclude           = ($AppExclude -join ', ')
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'App'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant               = $DomainName
            displayName          = "Could not connect to Tenant: $($_.Exception.Message)"
            publishingState      = 'Error'
            lastModifiedDateTime = (Get-Date).ToString('s')
            id                   = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'App'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
