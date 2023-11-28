using namespace System.Net

Function Invoke-RemoveExConnector {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter


    $Params = @{
        Identity = $request.query.guid
    }

    try {
        $Params = @{ Identity = $request.query.GUID }

        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Remove-$($Request.query.Type)Connector" -cmdParams $params
        $Result = "Deleted $($Request.query.guid)"
        Write-LogMessage -API 'TransportRules' -tenant $tenantfilter -message "Deleted transport rule $($Request.query.guid)" -sev Debug
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        $Result = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
