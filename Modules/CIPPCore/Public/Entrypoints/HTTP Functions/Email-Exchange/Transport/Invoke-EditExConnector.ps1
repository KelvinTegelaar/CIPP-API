function Invoke-EditExConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Connector.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    try {
        $ConnectorState = $Request.Query.State ?? $Request.Body.State
        $State = if ($ConnectorState -eq 'Enable') { $true } else { $false }
        $Guid = $Request.Query.GUID ?? $Request.Body.GUID
        $Type = $Request.Query.Type ?? $Request.Body.Type
        $Params = @{
            Identity = $Guid
            Enabled  = $State
        }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-$($Type)Connector" -cmdParams $params -UseSystemMailbox $true
        $Result = "Set Connector $($Guid) to $($ConnectorState)"
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $TenantFilter -message "Set Connector $($Guid) to $($ConnectorState)" -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CIPPException -Exception $_
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $TenantFilter -message "Failed setting Connector $($Guid) to $($ConnectorState). Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
