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

    # AllTenants always uses the reporting database - the live path queries a single tenant's
    # Defender TVM API and cannot fan out across tenants within one request.
    if ($UseReportDB -eq 'true' -or $TenantFilter -eq 'AllTenants') {
        try {
            Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message 'running cached cve report' -sev 'info'
            $GraphRequest = Get-CIPPCVEReport -TenantFilter $TenantFilter -UseReportDB $true -ErrorAction Stop
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            Write-Host 'Error retrieving CVEs from report database:$($_.Exception.Message)'
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
            Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message 'Error retrieving CVEs from report database' -sev 'error'
        }
    } else {
        try {
            Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message 'running live cve report' -sev 'info'
            $GraphRequest = Get-CIPPCVEReport -TenantFilter $TenantFilter -UseReportDB $false -ErrorAction Stop
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            Write-Host 'Error retrieving live CVEs: $($_.Exception.Message)'
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
            Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message 'Error retrieving Live CVEs' -sev 'error'
        }
    }

    $SortedCves = $GraphRequest

    Return [HttpResponseContext]@{
    StatusCode = $StatusCode
    Body       = @( $SortedCves )
    }
}
