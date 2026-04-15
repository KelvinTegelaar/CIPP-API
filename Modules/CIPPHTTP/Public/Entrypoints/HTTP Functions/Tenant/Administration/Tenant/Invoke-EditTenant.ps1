function Invoke-EditTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
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
        $GroupTable = Get-CippTable -TableName 'TenantGroups'
        $StaticGroups = Get-CIPPAzDataTableEntity @GroupTable -Filter "PartitionKey eq 'TenantGroup' and GroupType ne 'dynamic'"
        $StaticGroupIds = $StaticGroups.RowKey
        $CurrentGroupMemberships = Get-CIPPAzDataTableEntity @GroupMembersTable -Filter "customerId eq '$customerId'"
        foreach ($Group in $tenantGroups) {
            # Only allow adding to static groups; dynamic group membership is managed by the orchestrator
            if ($StaticGroupIds -notcontains $Group.groupId) { continue }
            $GroupEntity = $CurrentGroupMemberships | Where-Object { $_.GroupId -eq $Group.groupId }
            if (!$GroupEntity) {
                $GroupEntity = @{
                    PartitionKey = 'Member'
                    RowKey       = '{0}-{1}' -f $Group.groupId, $customerId
                    GroupId      = $Group.groupId
                    customerId   = $customerId
                }
                Add-CIPPAzDataTableEntity @GroupMembersTable -Entity $GroupEntity -Force
                Write-LogMessage -headers $Headers -API $APINAME -tenant $Tenant.defaultDomainName -TenantId $Tenant.customerId -message "Added tenant to group '$($Group.groupName)'" -Sev 'Info'
            }
        }

        # Remove any static groups that are no longer selected (dynamic groups are managed by the orchestrator)
        if ($tenantGroups) {
            foreach ($Group in $CurrentGroupMemberships) {
                if ($StaticGroupIds -contains $Group.GroupId -and $tenantGroups.GroupId -notcontains $Group.GroupId) {
                    $GroupName = ($StaticGroups | Where-Object { $_.RowKey -eq $Group.GroupId }).Name
                    Remove-AzDataTableEntity @GroupMembersTable -Entity $Group
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $Tenant.defaultDomainName -TenantId $Tenant.customerId -message "Removed tenant from group '$GroupName'" -Sev 'Info'
                }
            }
        }
        $DomainBasedEntries = Get-CIPPAzDataTableEntity @GroupMembersTable -Filter "customerId eq '$($Tenant.defaultDomainName)'"
        if ($DomainBasedEntries) {
            foreach ($Entry in $DomainBasedEntries) {
                try {
                    # Add corrected GUID-based entry using the actual GUID
                    $NewEntry = @{
                        PartitionKey = 'Member'
                        RowKey       = '{0}-{1}' -f $Entry.GroupId, $Tenant.customerId
                        GroupId      = $Entry.GroupId
                        customerId   = $Tenant.customerId
                    }
                    Add-CIPPAzDataTableEntity @GroupMembersTable -Entity $NewEntry -Force
                    Remove-AzDataTableEntity @GroupMembersTable -Entity $Entry
                } catch {
                    Write-Host "Error migrating entry: $($_.Exception.Message)"
                }
            }
        }

        # Bust the TenantGroups cache so subsequent calls reflect the changes made above
        Get-TenantGroups -SkipCache | Out-Null

        $response = @{
            state      = 'success'
            resultText = 'Tenant details updated successfully'
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $response
            })
    } catch {
        Write-LogMessage -headers $Headers -tenant $Tenant.defaultDomainName -TenantId $Tenant.customerId -API $APINAME -message "Edit Tenant failed. The error is: $($_.Exception.Message)" -Sev 'Error'
        $response = @{
            state      = 'error'
            resultText = $_.Exception.Message
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $response
            })
    }
}
