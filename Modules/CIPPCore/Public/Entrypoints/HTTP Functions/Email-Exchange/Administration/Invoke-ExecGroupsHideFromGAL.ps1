using namespace System.Net

function Invoke-ExecGroupsHideFromGAL {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $GroupType = $Request.Query.GroupType ?? $Request.Body.GroupType
    $GroupID = $Request.Query.ID ?? $Request.Body.ID
    $HideFromGAL = $Request.Query.HideFromGAL ?? $Request.Body.HideFromGAL

    try {
        $Result = Set-CIPPGroupGAL -Id $GroupID -TenantFilter $TenantFilter -GroupType $GroupType -HiddenString $HideFromGAL -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Result) }
    }

}
