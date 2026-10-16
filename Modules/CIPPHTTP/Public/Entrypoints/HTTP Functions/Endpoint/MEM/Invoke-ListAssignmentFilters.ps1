function Invoke-ListAssignmentFilters {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists Intune assignment filters for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Get the tenant filter
    $TenantFilter = $Request.Query.tenantFilter
    $FilterId = $Request.Query.filterId
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    try {
        if (-not $FilterId -and ($TenantFilter -eq 'AllTenants' -or $UseReportDB)) {
            try {
                # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
                if ($Request.Query.manualPagination -eq $true) {
                    # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                    $PageSize = $Request.Query.PageSize -as [int]
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::OK
                            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                            Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'IntuneAssignmentFilters' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPAssignmentFilterReport -TenantFilter $Tenant -ErrorAction Stop }
                        })
                }
                $AssignmentFilters = Get-CIPPAssignmentFilterReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $AssignmentFilters = $_.Exception.Message
            }
            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($AssignmentFilters)
                })
        }

        if ($FilterId) {
            # Get specific filter
            $AssignmentFilters = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($FilterId)" -tenantid $TenantFilter
        } else {
            # Get all filters
            $AssignmentFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve assignment filters: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $AssignmentFilters = @()
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($AssignmentFilters)
        })
}
