using namespace System.Net

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
            $null = Set-CIPPAssignedPolicy -PolicyId $ID -TenantFilter $TenantFilter -GroupName $AssignTo -Type $Type -Headers $Headers
        }
        "Successfully edited policy for $($TenantFilter)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        "Failed to add policy for $($TenantFilter): $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $results }
        })

}
