Function Invoke-ListDomains {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Result = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter | Select-Object id, isdefault, isinitial | Sort-Object isdefault -Descending
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Result)
        })

}
