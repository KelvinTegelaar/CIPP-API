function Invoke-ListAssignmentFilters {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Get the tenant filter
    $TenantFilter = $Request.Query.tenantFilter
    $FilterId = $Request.Query.filterId

    try {
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
