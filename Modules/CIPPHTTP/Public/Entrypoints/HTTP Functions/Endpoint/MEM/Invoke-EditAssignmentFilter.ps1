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

    $TenantFilter = $Request.Body.tenantFilter

    try {
        $FilterId = $Request.Body.filterId
        $DisplayName = $Request.Body.displayName
        $Description = $Request.Body.description
        $Rule = $Request.Body.rule

        if (!$FilterId) {
            throw 'Filter ID is required'
        }

        # Build the update body
        # Note: Platform and assignmentFilterManagementType cannot be changed after creation per Graph API restrictions
        $UpdateBody = @{}

        if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
            $UpdateBody.displayName = $DisplayName
        }

        if ($null -ne $Description) {
            $UpdateBody.description = $Description
        }

        if (-not [string]::IsNullOrWhiteSpace($Rule)) {
            $UpdateBody.rule = $Rule
        }

        # Update the assignment filter
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$FilterId" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject $UpdateBody -Depth 10)

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Updated assignment filter $($DisplayName)" -Sev Info

        $Result = "Successfully updated assignment filter $($DisplayName)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to update assignment filter: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = "Failed to update assignment filter: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
