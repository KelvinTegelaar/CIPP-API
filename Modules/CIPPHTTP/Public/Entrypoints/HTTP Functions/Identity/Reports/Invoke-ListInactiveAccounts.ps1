Function Invoke-ListInactiveAccounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Lists user accounts that have not signed in for a configurable number of days (default 180), based on sign-in activity data.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ListInactiveAccounts'
    $TenantFilter = $Request.Query.tenantFilter
    $InactiveDays = if ($Request.Query.InactiveDays) { [int]$Request.Query.InactiveDays } else { 180 }

    try {
        # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
        if ($Request.Query.manualPagination -eq $true) {
            # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
            $PageSize = $Request.Query.PageSize -as [int]
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                    Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'Users' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPInactiveUsersReport -TenantFilter $Tenant -InactiveDays $InactiveDays -ErrorAction Stop }
                })
        }
        $GraphRequest = Get-CIPPInactiveUsersReport -TenantFilter $TenantFilter -InactiveDays $InactiveDays
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to retrieve inactive accounts: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
