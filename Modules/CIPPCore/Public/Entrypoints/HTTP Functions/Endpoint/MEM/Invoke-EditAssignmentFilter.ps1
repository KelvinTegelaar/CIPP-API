function Invoke-EditAssignmentFilter {
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

    $TenantFilter = $Request.Body.tenantFilter

    try {
        $FilterId = $Request.Body.filterId

        if (!$FilterId) {
            throw 'Filter ID is required'
        }

        # Build the update body
        # Note: Platform and assignmentFilterManagementType cannot be changed after creation per Graph API restrictions
        $UpdateBody = @{}

        if ($Request.Body.displayName) {
            $UpdateBody.displayName = $Request.Body.displayName
        }

        if ($null -ne $Request.Body.description) {
            $UpdateBody.description = $Request.Body.description
        }

        if ($Request.Body.rule) {
            $UpdateBody.rule = $Request.Body.rule
        }

        # Update the assignment filter
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$FilterId" -tenantid $TenantFilter -type PATCH -body ($UpdateBody | ConvertTo-Json -Depth 10)

        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Updated assignment filter $($Request.Body.displayName)" -Sev Info

        $Result = "Successfully updated assignment filter $($Request.Body.displayName)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Failed to update assignment filter: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = "Failed to update assignment filter: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
