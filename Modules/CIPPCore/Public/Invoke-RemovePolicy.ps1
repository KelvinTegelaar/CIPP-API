using namespace System.Net

Function Invoke-RemovePolicy {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $policyId = $Request.Query.ID
    if (!$policyId) { exit }
    try {

        #$unAssignRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($policyId)')/assign" -type POST -Body '{"assignments":[]}' -tenant $TenantFilter
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($Request.Query.URLName)('$($policyId)')" -type DELETE -tenant $TenantFilter
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Deleted $policyId" -Sev 'Info' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = 'Successfully deleted the policy' }

    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Could not delete policy $policyId. $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = "Could not delete policy: $($_.Exception.Message)" }

    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
