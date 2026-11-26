function Invoke-ListCyberInsuranceReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Reports.Read
    .SYNOPSIS
        Get the Cyber Insurance Readiness report for a tenant
    .DESCRIPTION
        Returns the 25 cyber insurance application questions for one tenant, each with its answer and supporting detail taken from the tenant's stored test results, plus summary counts and the age of the underlying data.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'The cyber insurance report runs against a single tenant' } })
    }

    try {
        $Body = Get-CIPPCyberInsuranceReport -TenantFilter $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Failed to build the cyber insurance report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to build the cyber insurance report: $($ErrorMessage.NormalizedError)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
