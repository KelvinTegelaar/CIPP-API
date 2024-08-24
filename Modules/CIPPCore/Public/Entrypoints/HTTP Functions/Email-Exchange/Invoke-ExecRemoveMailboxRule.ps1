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

    $APIName = 'Remove mailbox rule'
    $TenantFilter = $Request.Query.TenantFilter
    $RuleName = $Request.Query.ruleName
    $RuleId = $Request.Query.ruleId
    $Username = $Request.Query.userPrincipalName

    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -tenant $TenantFilter -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Remove the rule
    $Results = Remove-CIPPMailboxRule -userid $User -username $Username -TenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $User -RuleId $RuleId -RuleName $RuleName

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
