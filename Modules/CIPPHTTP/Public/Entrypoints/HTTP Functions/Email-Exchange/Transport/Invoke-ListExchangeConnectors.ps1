function Invoke-ListExchangeConnectors {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Connector.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })

}
