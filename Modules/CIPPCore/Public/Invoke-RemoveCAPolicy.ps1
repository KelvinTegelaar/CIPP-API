using namespace System.Net

Function Invoke-RemoveCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $policyId = $Request.Query.GUID
    if (!$policyId) { exit }
    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($policyId)" -type DELETE -tenant $TenantFilter
        Write-LogMessage -user $User -API $APINAME -message "Deleted CA Policy $policyId" -Sev 'Info' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = 'Successfully deleted the policy' }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -message "Could not delete CA policy $policyId. $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Could not delete policy: $($ErrorMessage.NormalizedError)" }

    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })


}
