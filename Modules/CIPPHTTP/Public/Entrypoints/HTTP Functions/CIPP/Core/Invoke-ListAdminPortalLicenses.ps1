function Invoke-ListAdminPortalLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Retrieves license information from the Microsoft 365 Admin Portal for a tenant, including low-friction trial allotments.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    try {
        $AdminPortalLicenses = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $TenantFilter -Uri 'https://admin.microsoft.com/fd/m365licensing/v3/licensedProducts?allotmentSourceOwnerType=User&allotmentSourceType=LowFrictionTrial&allotmentSourceState=Active,Deleted,Suspended,Lockout,Warning&displayNameLanguage=en-GB'

    } catch {
        Write-Warning 'Failed to get Admin Portal Licenses'
        $AdminPortalLicenses = @()
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($AdminPortalLicenses)
        })
}
