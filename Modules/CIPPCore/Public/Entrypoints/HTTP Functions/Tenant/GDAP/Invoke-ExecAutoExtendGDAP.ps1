Function Invoke-ExecAutoExtendGDAP {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Id = $Request.query.ID ?? $Request.Body.ID
    $Results = Set-CIPPGDAPAutoExtend -RelationShipid $Id

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })

}
