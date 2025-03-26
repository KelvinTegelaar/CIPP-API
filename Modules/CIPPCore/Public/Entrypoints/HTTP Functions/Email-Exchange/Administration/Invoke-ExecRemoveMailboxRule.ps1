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
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query or body of the request
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Body.TenantFilter
    $RuleName = $Request.Query.ruleName ?? $Request.Body.ruleName
    $RuleId = $Request.Query.ruleId ?? $Request.Body.ruleId
    $Username = $Request.Query.userPrincipalName ?? $Request.Body.userPrincipalName

    # Remove the rule
    $Results = Remove-CIPPMailboxRule -username $Username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -RuleId $RuleId -RuleName $RuleName

    if ($Results -like '*Could not delete*') {
        $StatusCode = [HttpStatusCode]::InternalServerError
    } else {
        $StatusCode = [HttpStatusCode]::OK
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })

}
