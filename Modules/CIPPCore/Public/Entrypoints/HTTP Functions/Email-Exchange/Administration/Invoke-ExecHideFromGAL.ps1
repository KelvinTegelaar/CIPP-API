using namespace System.Net

function Invoke-ExecHideFromGAL {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Support if the request is a POST or a GET. So to support legacy(GET) and new(POST) requests
    $UserId = $Request.Query.ID ?? $Request.Body.ID
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Body.tenantFilter
    $HideFromGAL = $Request.Query.HideFromGAL ?? $Request.Body.HideFromGAL
    $HideFromGAL = [System.Convert]::ToBoolean($HideFromGAL)

    try {
        $Result = Set-CIPPHideFromGAL -TenantFilter $TenantFilter -UserID $UserId -HideFromGAL $HideFromGAL -Headers $Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Result) }
    }

}
