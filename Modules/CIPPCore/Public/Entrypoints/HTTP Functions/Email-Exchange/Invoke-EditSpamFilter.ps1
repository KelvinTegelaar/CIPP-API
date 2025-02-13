using namespace System.Net

Function Invoke-EditSpamFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter

    $Params = @{
        Identity = $request.query.name
    }

    try {
        $cmdlet = if ($request.query.state -eq 'enable') { 'Enable-HostedContentFilterRule' } else { 'Disable-HostedContentFilterRule' }
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet $cmdlet -cmdParams $params -useSystemmailbox $true
        $Result = "Set Spamfilter rule to $($request.query.State)"
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenantfilter -message "Set Spamfilter rule $($Request.query.name) to $($request.query.State)" -sev Info
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenantfilter -message "Failed setting Spamfilter rule $($Request.query.guid) to $($request.query.State). Error:$ErrorMessage" -Sev 'Error'
        $Result = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
