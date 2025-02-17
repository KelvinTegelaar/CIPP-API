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
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $policyId = $Request.Query.ID ?? $Request.Body.ID
    if (!$policyId) { exit }
    try {
        #$unAssignRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($policyId)')/assign" -type POST -Body '{"assignments":[]}' -tenant $TenantFilter
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($policyId)" -type DELETE -tenant $TenantFilter
        $Result = "Successfully deleted app with $policyId"
        Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev 'Info' -tenant $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not delete app with $policyId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage

    }

    $Body = [pscustomobject]@{Results = "$Result" }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })


}
