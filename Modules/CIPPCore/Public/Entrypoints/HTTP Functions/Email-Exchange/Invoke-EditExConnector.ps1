using namespace System.Net

Function Invoke-EditExConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Connector.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter ?? $Request.Body.tenantfilter
    try {
        $ConnectorState = $Request.Query.State ?? $Request.Body.State
        $State = if ($ConnectorState -eq 'enable') { $true } else { $false }
        $Guid = $Request.Query.GUID ?? $Request.Body.GUID
        $type = $Request.Query.Type ?? $Request.Body.Type
        $Params = @{
            Identity = $Guid
            Enabled  = $State
        }
        $null = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Set-$($Type)Connector" -cmdParams $params -UseSystemMailbox $true
        $Result = "Set Connector $($Guid) to $($ConnectorState)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenantfilter -message "Set Connector $($Request.query.guid) to $($request.query.State)" -sev 'Info'
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenantfilter -message "Failed setting Connector $($Guid) to $($ConnectorState). Error:$($_.Exception.Message)" -Sev 'Error'
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        $Result = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
