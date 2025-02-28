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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $policyId = $Request.Query.GUID ?? $Request.Body.GUID
    if (!$policyId) { exit }
    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($policyId)" -type DELETE -tenant $TenantFilter -asapp $true
        $Result = "Deleted CA Policy $($policyId)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not delete CA policy with ID $($policyId) : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $body = [pscustomobject]@{'Results' = $Result }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })


}
