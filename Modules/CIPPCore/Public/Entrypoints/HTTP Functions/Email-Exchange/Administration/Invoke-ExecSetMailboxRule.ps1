using namespace System.Net

function Invoke-ExecSetMailboxRule {
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
        $Results = 'No state provided for mailbox rule'
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -tenant $TenantFilter
        $StatusCode = [HttpStatusCode]::BadRequest
        return @{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        }
    }

    try {
        $Results = Set-CIPPMailboxRule @SetCIPPMailboxRuleParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
