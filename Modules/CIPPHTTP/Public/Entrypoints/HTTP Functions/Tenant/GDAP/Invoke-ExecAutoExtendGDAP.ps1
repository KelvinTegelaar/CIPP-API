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
    # The id is placed in a Graph URL, so it must be a relationship id and nothing else.
    if (-not (Test-CIPPGDAPRelationshipId -Id "$Id")) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Invalid relationship id' } })
    }
    $PartnerTenantId = $Request.Query.partnerTenantId ?? $Request.Body.partnerTenantId
    if (!$PartnerTenantId -or -not (Get-CIPPPartnerTenantList | Where-Object { $_.partnerTenantId -eq $PartnerTenantId })) {
        $PartnerTenantId = $env:TenantID
    }
    $Results = Set-CIPPGDAPAutoExtend -RelationShipid $Id -PartnerTenantId $PartnerTenantId

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })

}
