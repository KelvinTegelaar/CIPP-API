using namespace System.Net

Function Invoke-EditTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $customerId = $Request.Body.customerId
    $tenantAlias = $Request.Body.tenantAlias
    $tenantGroups = $Request.Body.tenantGroups

    $PropertiesTable = Get-CippTable -TableName 'TenantProperties'
    $Existing = Get-CIPPAzDataTableEntity @PropertiesTable -Filter "PartitionKey eq '$customerId'"
    $Tenant = Get-Tenants -TenantFilter $customerId
    $TenantTable = Get-CippTable -TableName 'Tenants'
    $GroupMembersTable = Get-CippTable -TableName 'TenantGroupMembers'

    try {
        $AliasEntity = $Existing | Where-Object { $_.RowKey -eq 'Alias' }
        if (!$tenantAlias) {
            if ($AliasEntity) {
                Write-Host 'Removing alias'
                Remove-AzDataTableEntity @PropertiesTable -Entity $AliasEntity
                $null = Get-Tenants -TenantFilter $customerId -TriggerRefresh
            }
        } else {
            $aliasEntity = @{
                PartitionKey = $customerId
                RowKey       = 'Alias'
                Value        = $tenantAlias
            }
            $null = Add-CIPPAzDataTableEntity @PropertiesTable -Entity $aliasEntity -Force
            Write-Host "Setting alias to $tenantAlias"
            $Tenant | Add-Member -NotePropertyName 'originalDisplayName' -NotePropertyValue $tenant.displayName -Force
            $Tenant.displayName = $tenantAlias
            $null = Add-CIPPAzDataTableEntity @TenantTable -Entity $Tenant -Force
        }

        # Update tenant groups
        $CurrentMembers = Get-CIPPAzDataTableEntity @GroupMembersTable -Filter "customerId eq '$customerId'"
        foreach ($Group in $tenantGroups) {
            $GroupEntity = $CurrentMembers | Where-Object { $_.GroupId -eq $Group.groupId }
            if (!$GroupEntity) {
                $GroupEntity = @{
                    PartitionKey = 'Member'
                    RowKey       = '{0}-{1}' -f $Group.groupId, $customerId
                    GroupId      = $Group.groupId
                    customerId   = $customerId
                }
                Add-CIPPAzDataTableEntity @GroupMembersTable -Entity $GroupEntity -Force
            }
        }

        # Remove any groups that are no longer selected
        foreach ($Group in $CurrentMembers) {
            if ($tenantGroups -notcontains $Group.GroupId) {
                Remove-AzDataTableEntity @GroupMembersTable -Entity $Group
            }
        }

        $response = @{
            state      = 'success'
            resultText = 'Tenant details updated successfully'
        }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $response
            })
    } catch {
        Write-LogMessage -headers $Request.Headers -tenant $customerId -API $APINAME -message "Edit Tenant failed. The error is: $($_.Exception.Message)" -Sev 'Error'
        $response = @{
            state      = 'error'
            resultText = $_.Exception.Message
        }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $response
            })
    }
}
