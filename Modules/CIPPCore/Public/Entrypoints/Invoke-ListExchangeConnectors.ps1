using namespace System.Net

Function Invoke-ListExchangeConnectors {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Connector.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter

    $Results = try {
        New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-OutboundConnector' | Select-Object *, @{n = 'cippconnectortype'; e = { 'outbound' } }
        New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-InboundConnector' | Select-Object *, @{n = 'cippconnectortype'; e = { 'Inbound' } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })

}
