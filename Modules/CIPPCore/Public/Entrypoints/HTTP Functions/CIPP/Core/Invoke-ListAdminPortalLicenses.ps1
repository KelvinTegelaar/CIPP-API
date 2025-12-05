function Invoke-ListAdminPortalLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    try {
        $AdminPortalLicenses = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $TenantFilter -Uri 'https://admin.microsoft.com/admin/api/tenant/accountSkus'
    } catch {
        Write-Warning 'Failed to get Admin Portal Licenses'
        $AdminPortalLicenses = @()
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($AdminPortalLicenses)
        })
}
