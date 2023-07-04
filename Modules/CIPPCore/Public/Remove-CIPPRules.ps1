function Remove-CIPPRules {
    [CmdletBinding()]
    param (
        $userid,
        $username,
        $TenantFilter,
        $APIName = "Rules Removal",
        $ExecutingUser
    )

    try {
        $rules = New-ExoRequest -tenantid $TenantFilter -cmdlet "Get-InboxRule" -cmdParams @{mailbox = $userid } 
        if ($rules -eq $null) {
            Write-LogMessage -user $ExecutingUser -API $APIName -message "No Rules for $($userid) to delete" -Sev "Info" -tenant $TenantFilter
            return "No rules for $($userid) to delete"
        }
        else {
            ForEach ($rule in $rules) {
                New-ExoRequest -tenantid $TenantFilter -cmdlet "Remove-InboxRule" -Anchor $userid -cmdParams @{Identity = $rule.Identity }
            }
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Deleted Rules for $($userid)" -Sev "Info" -tenant $TenantFilter
            return "Deleted Rules for $($userid)"
        }
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not delete rules for $($userid): $($_.Exception.Message)" -Sev "Error" -tenant $TenantFilter
        return "Could not delete rules for $($userid). Error: $($_.Exception.Message)"
    }
}
