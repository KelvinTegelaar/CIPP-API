function Invoke-ListCSPLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Lists CSP (Cloud Solution Provider) license subscriptions for a tenant via the enabled CSP integration (Sherweb or External CSP).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    $Provider = try { Get-CIPPCSPProvider } catch { 'Sherweb' }
    try {
        if ($Provider -eq 'ExternalCSP') {
            $Result = Invoke-ExternalCSPRequest -Action Subscriptions -TenantFilter $TenantFilter
        } else {
            $Result = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Reason = $_.Exception.Message
        $Result = if ($Provider -eq 'ExternalCSP') {
            "Could not load CSP licenses. $Reason"
        } elseif ($Reason -eq 'No Sherweb mapping found') {
            'This tenant is not mapped to a Sherweb customer. Map it under Integrations > Sherweb > Tenant Mapping.'
        } else {
            "Could not load CSP licenses from Sherweb. Check that the Sherweb integration is enabled and its credentials are valid. $Reason"
        }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Result)
    }

}
