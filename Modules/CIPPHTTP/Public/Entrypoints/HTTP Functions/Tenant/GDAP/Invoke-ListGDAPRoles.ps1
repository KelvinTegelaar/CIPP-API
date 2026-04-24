Function Invoke-ListGDAPRoles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName 'GDAPRoles'
    $Groups = Get-CIPPAzDataTableEntity @Table

    $MappedGroups = foreach ($Group in $Groups) {
        [PSCustomObject]@{
            GroupName        = $Group.GroupName
            GroupId          = $Group.GroupId
            RoleName         = $Group.RoleName
            roleDefinitionId = $Group.roleDefinitionId
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($MappedGroups)
        })

}
