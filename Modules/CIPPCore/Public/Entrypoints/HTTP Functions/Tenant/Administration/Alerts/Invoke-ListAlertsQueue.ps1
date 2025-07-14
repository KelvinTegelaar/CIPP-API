using namespace System.Net

function Invoke-ListAlertsQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
    $WebhookRules = Get-CIPPAzDataTableEntity @WebhookTable

    $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
    $ScheduledTasks = Get-CIPPAzDataTableEntity @ScheduledTasks | Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    $TenantList = Get-Tenants -IncludeErrors
    $AllTasksArrayList = [system.collections.generic.list[object]]::new()

    foreach ($Task in $WebhookRules) {
        $Conditions = $Task.Conditions | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
        $TranslatedConditions = ($Conditions | ForEach-Object { "When $($_.Property.label) is $($_.Operator.label) $($_.input.value)" }) -join ' and '
        $TranslatedActions = ($Task.Actions | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue).label -join ','
        $Tenants = ($Task.Tenants | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue)
        $TaskEntry = [PSCustomObject]@{
            Tenants         = @($Tenants.label)
            Conditions      = $TranslatedConditions
            excludedTenants = @($Task.excludedTenants | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue)
            Actions         = $TranslatedActions
            LogType         = $Task.type
            EventType       = 'Audit log Alert'
            RowKey          = $Task.RowKey
            PartitionKey    = $Task.PartitionKey
            RepeatsEvery    = 'When received'
            RawAlert        = @{
                Conditions   = @($Conditions)
                Actions      = @($($Task.Actions | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue))
                Tenants      = @($Tenants)
                type         = $Task.type
                RowKey       = $Task.RowKey
                PartitionKey = $Task.PartitionKey

            }
        }

        if ($AllowedTenants -notcontains 'AllTenants') {
            foreach ($Tenant in $Tenants) {
                if ($AllowedTenants -contains $Tenant.customerId) {
                    $AllTasksArrayList.Add($TaskEntry)
                    break
                }
            }
        } else {
            $AllTasksArrayList.Add($TaskEntry)
        }
    }

    foreach ($Task in $ScheduledTasks) {
        if ($Task.excludedTenants) {
            $ExcludedTenants = @($Task.excludedTenants)
        } else {
            $ExcludedTenants = @()
        }

        # Handle tenant group display information for alerts
        $TenantsForDisplay = @()
        if ($Task.TenantGroup) {
            try {
                $TenantGroupObject = $Task.TenantGroup | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($TenantGroupObject) {
                    # Create a tenant group object for display
                    $TenantGroupForDisplay = [PSCustomObject]@{
                        label = $TenantGroupObject.label
                        value = $TenantGroupObject.value
                        type  = 'Group'
                    }
                    $TenantsForDisplay = @($TenantGroupForDisplay)
                }
            } catch {
                Write-Warning "Failed to parse tenant group information for alert task $($Task.RowKey): $($_.Exception.Message)"
                # Fall back to regular tenant display
                $TenantsForDisplay = @($Task.Tenant)
            }
        } else {
            # For regular tenants, create a tenant object for consistent formatting
            $TenantForDisplay = [PSCustomObject]@{
                label = $Task.Tenant
                value = $Task.Tenant
                type  = 'Tenant'
            }
            $TenantsForDisplay = @($TenantForDisplay)
        }

        $TaskEntry = [PSCustomObject]@{
            RowKey          = $Task.RowKey
            PartitionKey    = $Task.PartitionKey
            excludedTenants = @($ExcludedTenants)
            Tenants         = $TenantsForDisplay
            Conditions      = $Task.Name
            Actions         = $Task.PostExecution
            LogType         = 'Scripted'
            EventType       = 'Scheduled Task'
            RepeatsEvery    = $Task.Recurrence
            RawAlert        = $Task
        }

        if ($AllowedTenants -notcontains 'AllTenants') {
            # For tenant groups, we need to expand and check access
            if ($Task.TenantGroup) {
                try {
                    $TenantGroupObject = $Task.TenantGroup | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($TenantGroupObject) {
                        # Create a tenant filter object for expansion
                        $TenantFilterForExpansion = @([PSCustomObject]@{
                                type  = 'Group'
                                value = $TenantGroupObject.value
                                label = $TenantGroupObject.label
                            })

                        # Expand the tenant group to individual tenants
                        $ExpandedTenants = Expand-CIPPTenantGroups -TenantFilter $TenantFilterForExpansion

                        # Check if user has access to any tenant in the group
                        $HasAccess = $false
                        foreach ($ExpandedTenant in $ExpandedTenants) {
                            $TenantInfo = $TenantList | Where-Object -Property defaultDomainName -EQ $ExpandedTenant.value
                            if ($TenantInfo -and $AllowedTenants -contains $TenantInfo.customerId) {
                                $HasAccess = $true
                                break
                            }
                        }

                        if ($HasAccess) {
                            $AllTasksArrayList.Add($TaskEntry)
                        }
                    }
                } catch {
                    Write-Warning "Failed to expand tenant group for access check: $($_.Exception.Message)"
                }
            } else {
                # Regular tenant access check
                $Tenant = $TenantList | Where-Object -Property defaultDomainName -EQ $Task.Tenant
                if ($AllowedTenants -contains $Tenant.customerId) {
                    $AllTasksArrayList.Add($TaskEntry)
                }
            }
        } else {
            $AllTasksArrayList.Add($TaskEntry)
        }
    }

    $finalList = ConvertTo-Json -InputObject @($AllTasksArrayList) -Depth 10
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $finalList
        })

}
