function Invoke-ListAlertsQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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
            AlertComment    = $Task.AlertComment
            CustomSubject   = $Task.CustomSubject
            RawAlert        = @{
                Conditions    = @($Conditions)
                Actions       = @($($Task.Actions | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue))
                Tenants       = @($Tenants)
                type          = $Task.type
                RowKey        = $Task.RowKey
                PartitionKey  = $Task.PartitionKey
                AlertComment  = $Task.AlertComment
                CustomSubject = $Task.CustomSubject
            }
        }

        if ($AllowedTenants -notcontains 'AllTenants') {
            $HasAccess = $false
            foreach ($Tenant in $Tenants) {
                if ($Tenant.type -eq 'Group') {
                    try {
                        $GroupFilter = @([PSCustomObject]@{
                                type  = 'Group'
                                value = $Tenant.value
                                label = $Tenant.label
                            })
                        $ExpandedGroupTenants = Expand-CIPPTenantGroups -TenantFilter $GroupFilter
                        foreach ($ExpandedTenant in $ExpandedGroupTenants) {
                            if ($AllowedTenants -contains $ExpandedTenant.addedFields.customerId) {
                                $HasAccess = $true
                                break
                            }
                        }
                    } catch {
                        Write-Warning "Failed to expand tenant group for webhook access check: $($_.Exception.Message)"
                    }
                } else {
                    if ($AllowedTenants -contains $Tenant.customerId) {
                        $HasAccess = $true
                    }
                }
                if ($HasAccess) { break }
            }
            if ($HasAccess) {
                $AllTasksArrayList.Add($TaskEntry)
            }
        } else {
            $AllTasksArrayList.Add($TaskEntry)
        }
    }

    foreach ($Task in $ScheduledTasks) {
        if ($Task.excludedTenants) {
            $ExcludedTenants = @($Task.excludedTenants -split ',' | Where-Object { $_ })
        } else {
            $ExcludedTenants = @()
        }

        # Handle tenant display information for alerts
        $TenantsForDisplay = @()
        if ($Task.Tenants) {
            # Multi tenant alert
            try {
                $TenantsParsed = $Task.Tenants | ConvertFrom-Json -Depth 10 -ErrorAction Stop
                $TenantsForDisplay = @($TenantsParsed | ForEach-Object {
                        [PSCustomObject]@{
                            label = $_.label ?? $_.value
                            value = $_.value
                            type  = $_.type ?? 'Tenant'
                        }
                    })
                $ExcludedTenants = @()
            } catch {
                Write-Warning "Failed to parse Tenants for alert task $($Task.RowKey): $($_.Exception.Message)"
                $TenantsForDisplay = @([PSCustomObject]@{
                        label = $Task.Tenant
                        value = $Task.Tenant
                        type  = 'Tenant'
                    })
            }
        } elseif ($Task.TenantGroup) {
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

        $TaskParameters = $Task.Parameters | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
        $ScriptName = $TaskParameters.InputValue.ScriptGuid.label ?? $null

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
            AlertComment    = $Task.AlertComment
            RawAlert        = $Task
            ScriptName      = $ScriptName
        }

        if ($AllowedTenants -notcontains 'AllTenants') {
            $HasAccess = $false
            if ($Task.TenantGroup) {
                # Expand legacy TenantGroup field and check access
                try {
                    $TenantGroupObject = $Task.TenantGroup | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($TenantGroupObject) {
                        $TenantFilterForExpansion = @([PSCustomObject]@{
                                type  = 'Group'
                                value = $TenantGroupObject.value
                                label = $TenantGroupObject.label
                            })
                        $ExpandedTenants = Expand-CIPPTenantGroups -TenantFilter $TenantFilterForExpansion
                        foreach ($ExpandedTenant in $ExpandedTenants) {
                            $TenantInfo = $TenantList | Where-Object -Property defaultDomainName -EQ $ExpandedTenant.value
                            if ($TenantInfo -and $AllowedTenants -contains $TenantInfo.customerId) {
                                $HasAccess = $true
                                break
                            }
                        }
                    }
                } catch {
                    Write-Warning "Failed to expand tenant group for access check: $($_.Exception.Message)"
                }
            } elseif ($Task.Tenants) {
                # Multi-tenant alert - may contain groups or individual tenants
                try {
                    $TenantsParsed = $Task.Tenants | ConvertFrom-Json -ErrorAction Stop
                    foreach ($TenantItem in $TenantsParsed) {
                        if ($TenantItem.type -eq 'Group') {
                            $GroupFilter = @([PSCustomObject]@{
                                    type  = 'Group'
                                    value = $TenantItem.value
                                    label = $TenantItem.label
                                })
                            $ExpandedGroupTenants = Expand-CIPPTenantGroups -TenantFilter $GroupFilter
                            foreach ($ExpandedTenant in $ExpandedGroupTenants) {
                                if ($AllowedTenants -contains $ExpandedTenant.addedFields.customerId) {
                                    $HasAccess = $true
                                    break
                                }
                            }
                        } else {
                            $TenantInfo = $TenantList | Where-Object -Property defaultDomainName -EQ $TenantItem.value
                            if ($TenantInfo -and $AllowedTenants -contains $TenantInfo.customerId) {
                                $HasAccess = $true
                            }
                        }
                        if ($HasAccess) { break }
                    }
                } catch {
                    Write-Warning "Failed to parse Tenants for access check on task $($Task.RowKey): $($_.Exception.Message)"
                }
            } else {
                # Regular single-tenant access check
                $Tenant = $TenantList | Where-Object -Property defaultDomainName -EQ $Task.Tenant
                if ($AllowedTenants -contains $Tenant.customerId) {
                    $HasAccess = $true
                }
            }
            if ($HasAccess) {
                $AllTasksArrayList.Add($TaskEntry)
            }
        } else {
            $AllTasksArrayList.Add($TaskEntry)
        }
    }

    $finalList = ConvertTo-Json -InputObject @($AllTasksArrayList) -Depth 10
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $finalList
        })

}
