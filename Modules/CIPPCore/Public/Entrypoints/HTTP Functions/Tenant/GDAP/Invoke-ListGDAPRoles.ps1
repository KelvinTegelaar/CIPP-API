using namespace System.Net

Function Invoke-ListGDAPRoles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers




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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($MappedGroups)
        })

}
