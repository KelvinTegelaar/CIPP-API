function Invoke-ListExternalTenantInfo {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $HttpResponse = [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = 'Default response, you should never see this'
    }

    try {
        if ($Request.Query.tenant) {
            $Tenant = $Request.Query.tenant

            # Normalize to tenantid and determine if tenant exists
            $OpenIdConfig = Invoke-RestMethod -Method GET "https://login.windows.net/$Tenant/.well-known/openid-configuration"
            $TenantId = $OpenIdConfig.token_endpoint.Split('/')[3]

            if ($TenantId) {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$TenantId')" -NoAuthCheck $true -tenantid $env:TenantID
                $StatusCode = [HttpStatusCode]::OK
                $HttpResponse.Body = [PSCustomObject]@{
                    GraphRequest = $GraphRequest
                    OpenIdConfig = $OpenIdConfig
                }
            } else {
                $HttpResponse.StatusCode = [HttpStatusCode]::BadRequest
                $HttpResponse.Body = "Tenant $($Tenant) not found"
            }
        } else {
            $HttpResponse.StatusCode = [HttpStatusCode]::BadRequest
            $HttpResponse.Body = 'Tenant parameter is required'
        }
    } catch {
        $HttpResponse.StatusCode = [HttpStatusCode]::InternalServerError
        $HttpResponse.Body = "Something went wrong while trying to get tenant info for tenant $($Tenant): $($_.Exception.Message)"
    }

    return [HttpResponseContext]$HttpResponse
}
