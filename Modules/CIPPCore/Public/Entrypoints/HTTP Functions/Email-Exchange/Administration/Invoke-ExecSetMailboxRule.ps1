using namespace System.Net

Function Invoke-ExecSetMailboxRule {
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
    $TenantFilter = $Request.Body.TenantFilter
    $RuleName = $Request.Body.ruleName
    $RuleId = $Request.Body.ruleId
    $Username = $Request.Body.userPrincipalName
    $Enable = $Request.Body.Enable -as [bool]
    $Disable = $Request.Body.Disable -as [bool]


    # Set the rule
    $SetCIPPMailboxRuleParams = @{
        Username     = $Username
        TenantFilter = $TenantFilter
        APIName      = $APIName
        Headers      = $Headers
        RuleId       = $RuleId
        RuleName     = $RuleName
    }
    if ($Enable -eq $true) {
        $SetCIPPMailboxRuleParams.Add('Enable', $true)
    } elseif ($Disable -eq $true) {
        $SetCIPPMailboxRuleParams.Add('Disable', $true)
    } else {
        Write-LogMessage -headers $Headers -API $APIName -message 'No state provided for mailbox rule' -Sev 'Error' -tenant $TenantFilter
        throw 'No state provided for mailbox rule'
    }

    $Results = Set-CIPPMailboxRule @SetCIPPMailboxRuleParams

    if ($Results -like '*Could not set*') {
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
