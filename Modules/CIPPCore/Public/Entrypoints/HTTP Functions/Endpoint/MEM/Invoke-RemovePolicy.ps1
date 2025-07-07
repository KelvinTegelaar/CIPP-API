using namespace System.Net

function Invoke-RemovePolicy {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $PolicyId = $Request.Query.ID ?? $Request.Body.ID
    $UrlName = $Request.Query.URLName ?? $Request.Body.URLName

    if (!$PolicyId) { exit }
    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($UrlName)('$($PolicyId)')" -type DELETE -tenant $TenantFilter
        $Results = "Successfully deleted the policy with ID: $($PolicyId)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev Info -tenant $TenantFilter
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not delete policy: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Results }
    }
}
