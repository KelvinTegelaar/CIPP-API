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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $request.Query.tenantFilter

    $Results = try {
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OutboundConnector' | Select-Object *, @{n = 'cippconnectortype'; e = { 'outbound' } }
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-InboundConnector' | Select-Object *, @{n = 'cippconnectortype'; e = { 'Inbound' } }
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
