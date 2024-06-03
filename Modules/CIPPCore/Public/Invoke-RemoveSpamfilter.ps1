using namespace System.Net

Function Invoke-RemoveSpamfilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Spamfilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter


    $Params = @{
        Identity = $request.query.name
    }

    try {
        $cmdlet = 'Remove-HostedContentFilterRule'
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet $cmdlet -cmdParams $params
        $cmdlet = 'Remove-HostedContentFilterPolicy'
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet $cmdlet -cmdParams $params
        $Result = "Deleted $($Request.query.name)"
        Write-LogMessage -API 'TransportRules' -tenant $tenantfilter -message "Deleted transport rule $($Request.query.name)" -sev Debug
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
