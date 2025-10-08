Function Invoke-ExecSetMailboxQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        $APIName = $Request.Params.CIPPEndpoint
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
        $Username = $request.body.user
        $Tenantfilter = $request.body.tenantfilter
        $quota = $Request.body.quota
        $Results = try {
            if ($Request.Body.ProhibitSendQuota) {
                $quota = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Username; ProhibitSendQuota = $quota }
                "Changed ProhibitSendQuota for $username - $($message)"
                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Changed ProhibitSendQuota for $username - $($message)" -Sev 'Info' -tenant $TenantFilter
            }
            if ($Request.Body.ProhibitSendReceiveQuota) {
                $quota = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Username; ProhibitSendReceiveQuota = $quota }
                "Changed ProhibitSendReceiveQuota for $username - $($message)"
                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Changed ProhibitSendReceiveQuota for $username - $($message)" -Sev 'Info' -tenant $TenantFilter
            }
            if ($Request.Body.IssueWarningQuota) {
                $quota = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Username; IssueWarningQuota = $quota }
                "Changed IssueWarningQuota for $username - $($message)"
                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Changed IssueWarningQuota for $username - $($message)" -Sev 'Info' -tenant $TenantFilter
            }
        } catch {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not adjust mailbox quota for $($username)" -Sev 'Error' -tenant $TenantFilter
            "Could not adjust mailbox quota for $($username). Error: $($_.Exception.Message)"
        }

        $body = [pscustomobject]@{'Results' = @($results) }
    } catch {
        $body = [pscustomobject]@{'Results' = @("Could not adjust mailbox quota: $($_.Exception.message)") }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
