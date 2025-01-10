using namespace System.Net

Function Invoke-RemoveExConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Connector.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter ?? $Request.Body.tenantfilter
    $Type = $Request.Query.Type ?? $Request.Body.Type
    try {
        $Guid = $Request.Query.GUID ?? $Request.Body.GUID
        $Params = @{ Identity = $Guid }
        $null = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Remove-$($Type)Connector" -cmdParams $params -useSystemMailbox $true
        $Result = "Deleted $($Guid)"
        Write-LogMessage -user $User -API $APIName -tenant $tenantfilter -message "Deleted transport rule $($Guid)" -sev Debug
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APIName -tenant $tenantfilter -message "Failed deleting transport rule $($Guid). Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
