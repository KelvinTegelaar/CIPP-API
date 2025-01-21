using namespace System.Net

Function Invoke-RemoveTransportRule {
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
    Write-LogMessage -user $ExecutingUser -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.body.tenantFilter
    $Identity = $Request.Query.guid ?? $Request.body.guid

    $Params = @{
        Identity = $Identity
    }

    try {
        $cmdlet = 'Remove-TransportRule'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $cmdlet -cmdParams $Params -UseSystemMailbox $true
        $Result = "Deleted $($Identity)"
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Deleted transport rule $($Identity)" -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed deleting transport rule $($Identity). Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
