using namespace System.Net

Function Invoke-ListSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SafeLinksPolicy.Read
    .DESCRIPTION
        This function is used to list the Safe Links policies in the tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $request.Query.tenantfilter

    try {
        $Policies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-SafeLinksPolicy' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'
        $Rules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-SafeLinksRule' | Select-Object -Property * -ExcludeProperty '*@odata.type' , '*@data.type'

        # Create output with calculated properties for rule details
        $Output = $Policies | Select-Object -Property *,
        @{ Name = 'PolicyName'; Expression = { $_.Name } },
        @{ Name = 'RuleName'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.Name } } } },
        @{ Name = 'Priority'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.Priority } } } },
        @{ Name = 'State'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.State } } } },
        @{ Name = 'SentTo'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.SentTo } } } },
        @{ Name = 'SentToMemberOf'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.SentToMemberOf } } } },
        @{ Name = 'RecipientDomainIs'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.RecipientDomainIs } } } },
        @{ Name = 'ExceptIfSentTo'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.ExceptIfSentTo } } } },
        @{ Name = 'ExceptIfSentToMemberOf'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.ExceptIfSentToMemberOf } } } },
        @{ Name = 'ExceptIfRecipientDomainIs'; Expression = { foreach ($rule in $Rules) { if ($rule.SafeLinksPolicy -eq $_.Name) { $rule.ExceptIfRecipientDomainIs } } } },
        @{ Name = 'Description'; Expression = { $_.AdminDisplayName } }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Output = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Output
        })

}
