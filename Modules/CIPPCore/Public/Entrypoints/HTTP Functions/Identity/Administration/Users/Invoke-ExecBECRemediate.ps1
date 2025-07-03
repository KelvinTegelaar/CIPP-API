using namespace System.Net

function Invoke-ExecBECRemediate {
    <#
    .SYNOPSIS
    Remediate Business Email Compromise (BEC) for a user
    
    .DESCRIPTION
    Performs remediation steps for a user suspected of Business Email Compromise (BEC), including password reset, disabling account, revoking sessions, removing MFA methods, and disabling inbox rules.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    
    .NOTES
    Group: Security
    Summary: Exec BEC Remediate
    Description: Performs remediation steps for a user suspected of Business Email Compromise (BEC), including password reset, disabling account, revoking sessions, removing MFA methods, and disabling inbox rules. Logs each step and handles errors.
    Tags: Security,BEC,Remediation,Threat Response,Azure AD
    Parameter: tenantFilter (string) [body] - Target tenant identifier
    Parameter: userid (string) [body] - User ID to remediate
    Parameter: username (string) [body] - User principal name for remediation
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array of status messages for each remediation step
    Response: On success: Array of success messages for each step
    Response: On error: Error message with HTTP 500 status
    Example: {
      "Results": [
        "Disabled 2 Inbox Rules for john.doe@contoso.com",
        "No Inbox Rules found for john.doe@contoso.com. We have not disabled any rules."
      ]
    }
    Error: Returns error details if the operation fails at any remediation step.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Body.tenantFilter
    $SuspectUser = $Request.Body.userid
    $Username = $Request.Body.username
    Write-Host $TenantFilter
    Write-Host $SuspectUser
    $Results = try {
        $Step = 'Reset Password'
        Set-CIPPResetPassword -UserID $Username -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers
        $Step = 'Disable Account'
        Set-CIPPSignInState -userid $Username -AccountEnabled $false -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers
        $Step = 'Revoke Sessions'
        Revoke-CIPPSessions -userid $SuspectUser -username $Username -Headers $Headers -APIName $APIName -tenantFilter $TenantFilter
        $Step = 'Remove MFA methods'
        Remove-CIPPUserMFA -UserPrincipalName $Username -TenantFilter $TenantFilter -Headers $Headers
        $Step = 'Disable Inbox Rules'
        $Rules = New-ExoRequest -anchor $Username -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $Username; IncludeHidden = $true }
        $RuleDisabled = 0
        $RuleFailed = 0
        if (($Rules | Measure-Object).Count -gt 0) {
            $Rules | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' } | ForEach-Object {
                try {
                    Set-CIPPMailboxRule -Username $Username -TenantFilter $TenantFilter -RuleId $_.Identity -RuleName $_.Name -Disable -APIName $APIName -Headers $Headers
                    $RuleDisabled++
                } catch {
                    $_.Exception.Message
                    $RuleFailed++
                }
            }
        }
        if ($RuleDisabled -gt 0) {
            "Disabled $RuleDisabled Inbox Rules for $Username"
        }
        else {
            "No Inbox Rules found for $Username. We have not disabled any rules."
        }

        if ($RuleFailed -gt 0) {
            "Failed to disable $RuleFailed Inbox Rules for $Username"
        }
        $StatusCode = [HttpStatusCode]::OK
        Write-LogMessage -API 'BECRemediate' -tenant $TenantFilter -message "Executed Remediation for $Username" -sev 'Info' -LogData @($Results)

    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = [pscustomobject]@{'Results' = "Failed to execute remediation. $($ErrorMessage.NormalizedError)" }
        Write-LogMessage -API 'BECRemediate' -tenant $TenantFilter -message "Executed Remediation for $Username failed at the $Step step" -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    $Results = [pscustomobject]@{'Results' = @($Results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
