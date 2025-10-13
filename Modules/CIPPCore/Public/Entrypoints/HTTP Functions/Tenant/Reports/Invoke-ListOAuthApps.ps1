Function Invoke-ListOAuthApps {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    if ($TenantFilter -eq 'AllTenants') { $Tenants = (Get-Tenants).defaultDomainName } else { $Tenants = $TenantFilter }

    try {
        $GraphRequest = foreach ($Tenant in $Tenants) {
            try {
                $ServicePrincipals = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=id,displayName,appid" -tenantid $Tenant
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/oauth2PermissionGrants' -tenantid $Tenant | ForEach-Object {
                    $CurrentServicePrincipal = ($ServicePrincipals | Where-Object -Property id -EQ $_.clientId)
                    [PSCustomObject]@{
                        Tenant        = $Tenant
                        Name          = $CurrentServicePrincipal.displayName
                        ApplicationID = $CurrentServicePrincipal.appid
                        ObjectID      = $_.clientId
                        Scope         = ($_.scope -join ',')
                        StartTime     = $_.startTime
                    }
                }
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                continue
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
