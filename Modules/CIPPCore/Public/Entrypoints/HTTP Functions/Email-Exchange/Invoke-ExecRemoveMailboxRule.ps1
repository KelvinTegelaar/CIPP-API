using namespace System.Net

Function Invoke-ExecRemoveMailboxRule {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Query.TenantFilter
    $RuleName = $Request.Query.ruleName ?? $Request.Body.ruleName
    $RuleId = $Request.Query.ruleId ?? $Request.Body.ruleId
    $Username = $Request.Query.userPrincipalName ?? $Request.Body.userPrincipalName

    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message 'Accessed this API' -Sev 'Debug'

    # Remove the rule
    $Results = Remove-CIPPMailboxRule -username $Username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -RuleId $RuleId -RuleName $RuleName

    if ($Results -like '*Could not delete*') {
        $StatusCode = [HttpStatusCode]::Forbidden
    } else {
        $StatusCode = [HttpStatusCode]::OK
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })

}
