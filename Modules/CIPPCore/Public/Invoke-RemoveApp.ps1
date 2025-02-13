using namespace System.Net

Function Invoke-RemoveApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $User = $Request.Headers
    Write-LogMessage -Headers $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $policyId = $Request.Query.ID
    if (!$policyId) { exit }
    try {
        #$unAssignRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($policyId)')/assign" -type POST -Body '{"assignments":[]}' -tenant $TenantFilter
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($policyId)" -type DELETE -tenant $TenantFilter
        Write-LogMessage -Headers $User -API $APINAME -message "Deleted $policyId" -Sev 'Info' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = 'Successfully deleted the application' }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $User -API $APINAME -message "Could not delete app $policyId. $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Could not delete this application: $($ErrorMessage.NormalizedError)" }

    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
