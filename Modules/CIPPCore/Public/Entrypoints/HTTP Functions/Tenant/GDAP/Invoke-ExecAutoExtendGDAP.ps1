using namespace System.Net

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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })

}
