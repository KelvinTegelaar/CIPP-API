using namespace System.Net

Function Invoke-EditTransportRule {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $ExecutingUser = $Request.headers.'x-ms-client-principal'
    Write-LogMessage -user $ExecutingUser -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.body.tenantFilter
    $Identity = $Request.Query.guid ?? $Request.body.guid
    $State = $Request.Query.state ?? $Request.body.state

    $Params = @{
        Identity = $Identity
    }

    try {
        $cmdlet = if ($State -eq 'enable') { 'Enable-TransportRule' } else { 'Disable-TransportRule' }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $cmdlet -cmdParams $params -UseSystemMailbox $true
        $Result = "Set transport rule $($Identity) to $($State)"
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $TenantFilter -message "Failed setting transport rule $($Identity) to $($State). Error:$($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
