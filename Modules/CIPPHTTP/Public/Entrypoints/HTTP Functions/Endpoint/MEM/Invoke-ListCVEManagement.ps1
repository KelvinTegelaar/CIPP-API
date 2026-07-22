function Invoke-ListCVEManagement {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Security.Read
    #>

    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    try {
        if ($UseReportDB -eq 'true') {
            $GraphRequest = Get-CIPPCVEReport -TenantFilter $TenantFilter -UseReportDB $true -ErrorAction Stop
        } else {
            $GraphRequest = Get-CIPPCVEReport -TenantFilter $TenantFilter -UseReportDB $false -ErrorAction Stop
        }
        $StatusCode = [HttpStatusCode]::OK
        $SortedCves = $GraphRequest
        Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message "running cve report" -sev 'info'
    } catch {
        Write-Host "Error retrieving CVEs from report database: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $_.Exception.Message
        Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message "Error retrieving CVEs: $GraphRequest" -sev 'info'
    }

    Return [HttpResponseContext]@{
    StatusCode = $StatusCode
    Body       = @( $SortedCves )
    }
}
