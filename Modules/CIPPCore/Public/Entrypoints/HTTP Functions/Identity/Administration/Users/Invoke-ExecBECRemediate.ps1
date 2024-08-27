using namespace System.Net

Function Invoke-ExecBECRemediate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'

    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $request.body.tenantfilter
    $SuspectUser = $request.body.userid
    $username = $request.body.username
    Write-Host $TenantFilter
    Write-Host $SuspectUser
    $Results = try {
        $Step = 'Reset Password'
        Set-CIPPResetPassword -userid $username -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $User
        $Step = 'Disable Account'
        Set-CIPPSignInState -userid $username -AccountEnabled $false -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $User
        $Step = 'Revoke Sessions'
        Revoke-CIPPSessions -userid $SuspectUser -username $request.body.username -ExecutingUser $User -APIName $APINAME -tenantFilter $TenantFilter

        $Step = 'Disable Inbox Rules'
        $Rules = New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $username; IncludeHidden = $true }
        $RuleDisabled = 0
        $RuleFailed = 0
        if (($Rules | Measure-Object).Count -gt 0) {
            $Rules | Where-Object { $_.Name -ne 'Junk E-Mail Rule' } | ForEach-Object {
                try {
                    $null = New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'Disable-InboxRule' -cmdParams @{Confirm = $false; Identity = $_.Identity }
                    "Disabled Inbox Rule '$($_.Identity)' for $username"
                    $RuleDisabled++
                } catch {
                    "Failed to disable Inbox Rule '$($_.Identity)' for $username"
                    $RuleFailed++
                }
            }
        }
        if ($RuleDisabled -gt 0) {
            "Disabled $RuleDisabled Inbox Rules for $username"
        } else {
            "No Inbox Rules found for $username. We have not disabled any rules."
        }

        if ($RuleFailed -gt 0) {
            "Failed to disable $RuleFailed Inbox Rules for $username"
        }

        Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for $username" -sev 'Info'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $results = [pscustomobject]@{'Results' = "Failed to execute remediation. $($ErrorMessage.NormalizedError)" }
        Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for $username failed at the $Step step" -sev 'Error' -LogData $ErrorMessage
    }
    $results = [pscustomobject]@{'Results' = @($Results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
