using namespace System.Net

Function Invoke-RemovePolicy {
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
    Write-LogMessage -headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.body.tenantFilter
    $PolicyId = $Request.Query.ID ?? $Request.body.ID
    $UrlName = $Request.Query.URLName ?? $Request.body.URLName

    if (!$PolicyId) { exit }
    try {

        # $unAssignRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($PolicyId)')/assign" -type POST -Body '{"assignments":[]}' -tenant $TenantFilter
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($UrlName)('$($PolicyId)')" -type DELETE -tenant $TenantFilter
        $Results = "Successfully deleted the policy with ID: $($PolicyId)"
        Write-LogMessage -headers $Headers -API $APINAME -message $Results -Sev Info -tenant $TenantFilter
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not delete policy: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APINAME -message $Results -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $Body = [pscustomobject]@{'Results' = "$Results" }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })


}
