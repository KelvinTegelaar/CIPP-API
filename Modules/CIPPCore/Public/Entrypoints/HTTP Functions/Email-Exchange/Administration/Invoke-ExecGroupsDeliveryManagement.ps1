using namespace System.Net

function Invoke-ExecGroupsDeliveryManagement {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $GroupType = $Request.Query.GroupType ?? $Request.Body.GroupType
    $OnlyAllowInternal = $Request.Query.OnlyAllowInternal ?? $Request.Body.OnlyAllowInternal
    $ID = $Request.Query.ID ?? $Request.Body.ID

    try {
        $Result = Set-CIPPGroupAuthentication -ID $ID -GroupType $GroupType -OnlyAllowInternal $OnlyAllowInternal -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
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
