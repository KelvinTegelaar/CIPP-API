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
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter


    $Params = @{
        Identity = $request.query.guid
    }

    try {
        $cmdlet = 'Remove-TransportRule'
        $null = New-ExoRequest -tenantid $Tenantfilter -cmdlet $cmdlet -cmdParams $params -UseSystemMailbox $true
        $Result = "Deleted $($Request.query.guid)"
        Write-LogMessage -user $User -API $APIName -tenant $tenantfilter -message "Deleted transport rule $($Request.query.guid)" -sev Debug
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        Write-LogMessage -user $User -API $APIName -tenant $tenantfilter -message "Failed deleting transport rule $($Request.query.guid). Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
