using namespace System.Net

Function Invoke-ListConnectionFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.ConnectionFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter

    try {
        $Policies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedConnectionFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Policies = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Policies)
        })

}
