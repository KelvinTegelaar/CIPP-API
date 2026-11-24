function Invoke-RemoveCrossTenantPartner {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    .DESCRIPTION
        Removes a partner organisation from a tenant's cross-tenant access settings, so the default settings apply to it again.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Tenant ID of the partner organisation to remove
    $PartnerTenantId = "$($Request.Body.partnerTenantId)".Trim()
    $ParsedId = [guid]::Empty
    if (-not [guid]::TryParse($PartnerTenantId, [ref]$ParsedId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'partnerTenantId must be a tenant ID.' }
            })
    }

    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/$PartnerTenantId" -tenantid $TenantFilter -type DELETE -AsApp $true
        $Result = "Removed partner organisation $PartnerTenantId. It can take a minute to leave the list."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Result = "Failed to remove partner organisation $($PartnerTenantId): $ErrorMessage"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
