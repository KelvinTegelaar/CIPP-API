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
