Function Invoke-ListSpamfilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Tenantfilter = $request.Query.tenantfilter

    try {
        $Policies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
        $RuleState = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterRule' | Select-Object * -ExcludeProperty *odata*, *data.type*
        $GraphRequest = $Policies | Select-Object *, @{l = 'ruleState'; e = { $name = $_.name; ($RuleState | Where-Object name -EQ $name).State } }, @{l = 'rulePrio'; e = { $name = $_.name; ($RuleState | Where-Object name -EQ $name).Priority } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
