function Invoke-ListTenantGroups {
    <#
    .SYNOPSIS
        Entrypoint for listing tenant groups
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $groupFilter = $Request.Query.groupId ?? $Request.Body.groupId
    $includeUsage = $Request.Query.includeUsage ?? $Request.Body.includeUsage
    $TenantGroups = (Get-TenantGroups -GroupId $groupFilter -SkipCache) ?? @()

    if ($includeUsage -eq 'true') {
        $UsageByGroup = @{}
        foreach ($Group in $TenantGroups) {
            $UsageByGroup[$Group.Id] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }

        $AddGroupUsage = {
            param($FilterArray, $UsedIn, $Name, $Type)
            foreach ($Filter in $FilterArray) {
                if ($Filter.type -eq 'Group' -and $Filter.value -and $UsageByGroup.ContainsKey($Filter.value)) {
                    $UsageByGroup[$Filter.value].Add([PSCustomObject]@{
                        UsedIn = $UsedIn
                        Name   = $Name
                        Type   = $Type
                    })
                }
            }
        }

        # Standards Templates
        $TemplateTable = Get-CippTable -tablename 'templates'
        $TemplateFilter = "PartitionKey eq 'StandardsTemplateV2'"
        $Templates = Get-CIPPAzDataTableEntity @TemplateTable -Filter $TemplateFilter

        foreach ($Template in $Templates) {
            try {
                $TemplateData = $Template.JSON | ConvertFrom-Json
                $TemplateName = $TemplateData.templateName ?? $Template.RowKey
                if ($TemplateData.tenantFilter) {
                    & $AddGroupUsage $TemplateData.tenantFilter 'Standards Template' $TemplateName 'Tenant Filter'
                }
                if ($TemplateData.excludedTenants) {
                    & $AddGroupUsage $TemplateData.excludedTenants 'Standards Template' $TemplateName 'Excluded Tenants'
                }
            } catch {
                Write-Warning "Failed to parse standards template $($Template.RowKey): $($_.Exception.Message)"
            }
        }

        # Scheduled Tasks
        $TaskTable = Get-CippTable -tablename 'ScheduledTasks'
        $TaskFilter = "PartitionKey eq 'ScheduledTask'"
        $Tasks = Get-CIPPAzDataTableEntity @TaskTable -Filter $TaskFilter

        foreach ($Task in $Tasks) {
            if ($Task.TenantGroup) {
                try {
                    $TenantGroupObject = $Task.TenantGroup | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($TenantGroupObject.value -and $UsageByGroup.ContainsKey($TenantGroupObject.value)) {
                        $UsageByGroup[$TenantGroupObject.value].Add([PSCustomObject]@{
                            UsedIn = 'Scheduled Task'
                            Name   = $Task.Name ?? $Task.RowKey
                            Type   = 'Tenant Filter'
                        })
                    }
                } catch {
                    Write-Warning "Failed to parse tenant group for task $($Task.RowKey): $($_.Exception.Message)"
                }
            }
        }

        # Dynamic Group Rules referencing other groups
        foreach ($Group in $TenantGroups) {
            if ($Group.GroupType -eq 'dynamic' -and $Group.DynamicRules) {
                foreach ($Rule in $Group.DynamicRules) {
                    if ($Rule.property -eq 'TenantGroup' -and $Rule.value -and $UsageByGroup.ContainsKey($Rule.value)) {
                        $UsageByGroup[$Rule.value].Add([PSCustomObject]@{
                            UsedIn = 'Dynamic Group Rule'
                            Name   = $Group.Name
                            Type   = 'Rule Reference'
                        })
                    }
                }
            }
        }

        # Webhook Rules
        $WebhookTable = Get-CippTable -tablename 'WebhookRules'
        $WebhookRules = Get-CIPPAzDataTableEntity @WebhookTable

        foreach ($Rule in $WebhookRules) {
            try {
                $RuleName = $Rule.Name ?? $Rule.RowKey
                if ($Rule.Tenants) {
                    $Tenants = $Rule.Tenants | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($Tenants) {
                        & $AddGroupUsage $Tenants 'Alert Rule' $RuleName 'Tenant Filter'
                    }
                }
                if ($Rule.excludedTenants) {
                    $ExclTenants = $Rule.excludedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($ExclTenants) {
                        & $AddGroupUsage $ExclTenants 'Alert Rule' $RuleName 'Excluded Tenants'
                    }
                }
            } catch {
                Write-Warning "Failed to parse webhook rule $($Rule.RowKey): $($_.Exception.Message)"
            }
        }

        # Custom Roles
        $RolesTable = Get-CippTable -tablename 'CustomRoles'
        $CustomRoles = Get-CIPPAzDataTableEntity @RolesTable

        foreach ($Role in $CustomRoles) {
            try {
                $RoleName = $Role.Name ?? $Role.RowKey
                if ($Role.AllowedTenants) {
                    $AllowedTenants = $Role.AllowedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($AllowedTenants) {
                        & $AddGroupUsage $AllowedTenants 'Custom Role' $RoleName 'Allowed Tenants'
                    }
                }
                if ($Role.BlockedTenants) {
                    $BlockedTenants = $Role.BlockedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($BlockedTenants) {
                        & $AddGroupUsage $BlockedTenants 'Custom Role' $RoleName 'Blocked Tenants'
                    }
                }
            } catch {
                Write-Warning "Failed to parse custom role $($Role.RowKey): $($_.Exception.Message)"
            }
        }

        # Custom Data Mappings
        $MappingsTable = Get-CippTable -tablename 'CustomDataMappings'
        $Mappings = Get-CIPPAzDataTableEntity @MappingsTable

        foreach ($Mapping in $Mappings) {
            try {
                $MappingName = $Mapping.Name ?? $Mapping.RowKey
                if ($Mapping.tenantFilter) {
                    $TenantFilters = $Mapping.tenantFilter | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($TenantFilters) {
                        if ($TenantFilters -isnot [System.Array]) { $TenantFilters = @($TenantFilters) }
                        & $AddGroupUsage $TenantFilters 'Data Mapping' $MappingName 'Tenant Filter'
                    }
                }
            } catch {
                Write-Warning "Failed to parse custom data mapping $($Mapping.RowKey): $($_.Exception.Message)"
            }
        }

        foreach ($Group in $TenantGroups) {
            $Group | Add-Member -MemberType NoteProperty -Name 'Usage' -Value @($UsageByGroup[$Group.Id]) -Force
        }
    }

    $Body = @{ Results = @($TenantGroups) }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
