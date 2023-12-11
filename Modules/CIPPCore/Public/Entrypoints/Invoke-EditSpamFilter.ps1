using namespace System.Net

Function Invoke-EditSpamFilter {
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
        Identity = $request.query.name
    }

    try {
        $cmdlet = if ($request.query.state -eq 'enable') { 'Enable-HostedContentFilterRule' } else { 'Disable-HostedContentFilterRule' }
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet $cmdlet -cmdParams $params
        $Result = "Set Spamfilter rule to $($request.query.State)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenantfilter -message "Set Spamfilter rule $($Request.query.name) to $($request.query.State)" -sev Info
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenantfilter -message "Failed setting Spamfilter rule $($Request.query.guid) to $($request.query.State). Error:$($_.Exception.Message)" -Sev 'Error'
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        $Result = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
