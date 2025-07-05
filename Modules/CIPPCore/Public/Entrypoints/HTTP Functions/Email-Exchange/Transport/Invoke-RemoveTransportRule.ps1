using namespace System.Net

function Invoke-RemoveTransportRule {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Identity = $Request.Query.guid ?? $Request.Body.guid

    try {
        $cmdlet = 'Remove-TransportRule'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $cmdlet -cmdParams @{Identity = $Identity } -UseSystemMailbox $true
        $Result = "Deleted $($Identity)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted transport rule $($Identity)" -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed deleting transport rule $($Identity). Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
