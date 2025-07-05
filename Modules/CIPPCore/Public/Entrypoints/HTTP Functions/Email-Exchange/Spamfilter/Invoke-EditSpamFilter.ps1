using namespace System.Net

function Invoke-EditSpamFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $request.Query.tenantFilter
    $Name = $Request.Query.name ?? $Request.Body.name
    $State = $State ?? $Request.Body.state

    try {
        $Cmdlet = if ($State -eq 'enable') { 'Enable-HostedContentFilterRule' } else { 'Disable-HostedContentFilterRule' }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams @{ Identity = $Name } -useSystemMailbox $true
        $Result = "Set Spamfilter rule $($Name) to $($State)"
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed setting Spamfilter rule $($Name) to $($State). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
