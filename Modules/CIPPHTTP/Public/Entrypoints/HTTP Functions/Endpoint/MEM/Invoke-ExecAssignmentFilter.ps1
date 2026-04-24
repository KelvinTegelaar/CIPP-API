function Invoke-ExecAssignmentFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev Debug

    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Body.tenantFilter

    try {
        $FilterId = $Request.Body.ID
        $Action = $Request.Body.Action

        if (!$FilterId) {
            throw 'Filter ID is required'
        }

        switch ($Action) {
            'Delete' {
                # Delete the assignment filter
                $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$FilterId" -tenantid $TenantFilter -type DELETE

                Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Deleted assignment filter with ID $FilterId" -Sev Info

                $Result = "Successfully deleted assignment filter"
                $StatusCode = [HttpStatusCode]::OK
            }
            default {
                throw "Unknown action: $Action"
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Failed to execute assignment filter action: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = "Failed to execute assignment filter action: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
