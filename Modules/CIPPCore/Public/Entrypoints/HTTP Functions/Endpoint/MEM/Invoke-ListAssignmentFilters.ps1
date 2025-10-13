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

    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev Debug

    # Get the tenant filter
    $TenantFilter = $Request.Query.TenantFilter

    try {
        if ($Request.Query.filterId) {
            # Get specific filter
            $AssignmentFilters = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($Request.Query.filterId)" -tenantid $TenantFilter
        } else {
            # Get all filters
            $AssignmentFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed to retrieve assignment filters: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $AssignmentFilters = @()
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($AssignmentFilters)
        })
}
