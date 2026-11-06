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
