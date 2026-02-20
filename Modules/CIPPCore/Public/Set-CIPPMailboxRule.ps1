function Set-CIPPMailboxRule {
    [CmdletBinding()]
    param (
        $UserId,
        $Username,
        $TenantFilter,
        $APIName = 'Set mailbox rules',
        $Headers,
        $RuleId,
        $RuleName,
        [switch]$Enable,
        [switch]$Disable
    )

    if ($Enable.IsPresent -eq $true) {
        $State = 'Enable'
    } elseif ($Disable.IsPresent -eq $true) {
        $State = 'Disable'
    } else {
        Write-LogMessage -headers $Headers -API $APIName -message 'No state provided for mailbox rule' -Sev 'Error' -tenant $TenantFilter
        throw 'No state provided for mailbox rule'
    }

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "$State-InboxRule" -Anchor $Username -cmdParams @{Identity = $RuleId; Mailbox = $UserId }
        Write-LogMessage -headers $Headers -API $APIName -message "Successfully set mailbox rule $($RuleName) for $($Username) to $($State)d" -Sev 'Info' -tenant $TenantFilter

        # Update the cached rule if it exists (without calling Exchange again)
        try {
            $EnabledValue = $State -eq 'Enable'
            Update-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -ItemId $RuleId -PropertyUpdates @{
                Enabled = $EnabledValue
            }
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Rule updated but failed to update cache: $($_.Exception.Message)" -Sev 'Warning' -tenant $TenantFilter
        }

        return "Successfully set mailbox rule $($RuleName) for $($Username) to $($State)d"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not set mailbox rule $($RuleName) for $($Username) to $($State)d. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Could not set mailbox rule $($RuleName) for $($Username) to $($State)d. Error: $($ErrorMessage.NormalizedError)"
    }

}
