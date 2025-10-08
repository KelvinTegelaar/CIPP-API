Function Invoke-ListGDAPInvite {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $RelationshipId = $Request.Query.RelationshipId

    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    if (![string]::IsNullOrEmpty($RelationshipId)) {
        $Invite = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($RelationshipId)'"
    } else {
        $Invite = Get-CIPPAzDataTableEntity @Table | ForEach-Object {
            $_.RoleMappings = @(try { $_.RoleMappings | ConvertFrom-Json } catch { $_.RoleMappings })
            $_
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Invite)
        })
}
