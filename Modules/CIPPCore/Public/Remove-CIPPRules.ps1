function Remove-CIPPRules {
    [CmdletBinding()]
    param (
        $userid,
        $username,
        $TenantFilter,
        $APIName = 'Rules Removal',
        $ExecutingUser
    )

    try {
        Write-Host "Checking rules for $username"
        $rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $username; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' }
        Write-Host "$($rules.count) rules found"
        if ($null -eq $rules) {
            Write-LogMessage -user $ExecutingUser -API $APIName -message "No Rules for $($username) to delete" -Sev 'Info' -tenant $TenantFilter
            return "No rules for $($username) to delete"
        } else {
            ForEach ($rule in $rules) {
                New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-InboxRule' -Anchor $username -cmdParams @{Identity = $rule.Identity }
            }
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Deleted Rules for $($username)" -Sev 'Info' -tenant $TenantFilter
            return "Deleted Rules for $($username)"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not delete rules for $($username): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not delete rules for $($username). Error: $($ErrorMessage.NormalizedError)"
    }
}
