Function Invoke-ListOAuthApps {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    try {
        if ($UseReportDB -eq 'true') {
            try {
                $GraphRequest = Get-CIPPOAuthAppsReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                Write-Host "Error retrieving OAuth apps from report database: $($_.Exception.Message)"
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Live data - single tenant only
        $ServicePrincipals = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=id,displayName,appid&`$top=999" -tenantid $TenantFilter
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/oauth2PermissionGrants?$top=999' -tenantid $TenantFilter | ForEach-Object {
            $CurrentServicePrincipal = ($ServicePrincipals | Where-Object -Property id -EQ $_.clientId)
            [PSCustomObject]@{
                Name          = $CurrentServicePrincipal.displayName
                ApplicationID = $CurrentServicePrincipal.appid
                ObjectID      = $_.clientId
                Scope         = ($_.scope -join ',')
                StartTime     = $_.startTime
            }
        }
        $StatusCode = [HttpStatusCode]::OK
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
