using namespace System.Net

function Invoke-RemoveAutopilotConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $ProfileId = $Request.Body.ID
    $DisplayName = $Request.Body.displayName
    $Assignments = $Request.Body.assignments

    try {
        # Validate required parameters
        if ([string]::IsNullOrEmpty($ProfileId)) {
            throw 'Profile ID is required'
        }

        if ([string]::IsNullOrEmpty($TenantFilter)) {
            throw 'Tenant filter is required'
        }

        # Call the helper function to delete the autopilot profile
        $params = @{
            ProfileId    = $ProfileId
            DisplayName  = $DisplayName
            TenantFilter = $TenantFilter
            Assignments  = $Assignments
            Headers      = $Headers
            APIName      = $APIName
        }
        $Result = Remove-CIPPAutopilotProfile @params
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = $_.Exception.Message
        $Result = $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })
}
