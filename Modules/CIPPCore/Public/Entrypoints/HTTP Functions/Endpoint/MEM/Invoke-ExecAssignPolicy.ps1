Function Invoke-ExecAssignPolicy {
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
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with the body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $ID = $request.Body.ID
    $Type = $Request.Body.Type
    $AssignTo = $Request.Body.AssignTo

    $AssignTo = if ($AssignTo -ne 'on') { $AssignTo }

    $results = try {
        if ($AssignTo) {
            $AssignmentResult = Set-CIPPAssignedPolicy -PolicyId $ID -TenantFilter $TenantFilter -GroupName $AssignTo -Type $Type -Headers $Headers
            if ($AssignmentResult) {
                # Check if it's a warning message (no groups found)
                if ($AssignmentResult -like "*No groups found*") {
                    $StatusCode = [HttpStatusCode]::BadRequest
                } else {
                    $StatusCode = [HttpStatusCode]::OK
                }
                $AssignmentResult
            } else {
                $StatusCode = [HttpStatusCode]::OK
                "Successfully edited policy for $($TenantFilter)"
            }
        } else {
            $StatusCode = [HttpStatusCode]::OK
            "Successfully edited policy for $($TenantFilter)"
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        "Failed to add policy for $($TenantFilter): $($_.Exception.Message)"
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $results }
        })

}
