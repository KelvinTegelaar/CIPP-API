using namespace System.Net

function Invoke-ExecBECRemediate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
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
        } else {
            "No Inbox Rules found for $Username. We have not disabled any rules."
        }

        if ($RuleFailed -gt 0) {
            "Failed to disable $RuleFailed Inbox Rules for $Username"
        }
        $StatusCode = [HttpStatusCode]::OK
        Write-LogMessage -API 'BECRemediate' -tenant $TenantFilter -message "Executed Remediation for $Username" -sev 'Info' -LogData @($Results)

    } catch {
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
