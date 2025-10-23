function Invoke-ExecCreateDefaultGroups {
    <#
    .SYNOPSIS
        Create default tenant groups
    .DESCRIPTION
        This function creates a set of default tenant groups that are commonly used
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Groups.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Table = Get-CippTable -tablename 'TenantGroups'
        $Results = [System.Collections.Generic.List[object]]::new()
        $ExistingGroups = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantGroup' and Type eq 'dynamic'"
        $DefaultGroups = 

        foreach ($Group in $DefaultGroups) {
            # Check if group with same name already exists
            $ExistingGroup = $ExistingGroups | Where-Object -Property Name -EQ $group.Name
            if ($ExistingGroup) {
                $Results.Add(@{
                        resultText = "Group '$($Group.Name)' already exists, skipping"
                        state      = 'warning'
                    })
                continue
            }
            $GroupEntity = @{
                PartitionKey = 'TenantGroup'
                RowKey       = $groupId
                Name         = $Group.Name
                Description  = $Group.Description
                GroupType    = $Group.GroupType
                DynamicRules = $Group.DynamicRules
                RuleLogic    = $Group.RuleLogic
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GroupEntity -Force

            $Results.Add(@{
                    resultText = "Created default group: '$($Group.Name)'"
                    state      = 'success'
                })

            Write-LogMessage -API 'TenantGroups' -message "Created default tenant group: $($Group.Name)" -sev Info
        }

        $Body = @{ Results = $Results }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'TenantGroups' -message "Failed to create default groups: $ErrorMessage" -sev Error
        $Body = @{ Results = "Failed to create default groups: $ErrorMessage" }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $Body
            })
    }
}
