function Remove-CIPPMailboxRule {
    [CmdletBinding()]
    param (
        $UserId,
        $Username,
        $TenantFilter,
        $APIName = 'Mailbox Rules Removal',
        $Headers,
        $RuleId,
        $RuleName,
        [switch]$RemoveAllRules
    )

    if ($RemoveAllRules.IsPresent -eq $true) {
        # Delete all rules
        try {
            Write-Host "Checking rules for $Username"
            $Rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $Username; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' }
            Write-Host "$($Rules.count) rules found"
            if ($null -eq $Rules) {
                $Message = "No rules found for $($Username) to delete"
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
                return $Message
            } else {
                ForEach ($rule in $Rules) {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-InboxRule' -Anchor $Username -cmdParams @{Identity = $rule.Identity }
                }
                $Message = "Successfully deleted all rules for $($Username)"
                Write-LogMessage -headers $Headers -API $APIName -message "Deleted rules for $($Username)" -Sev 'Info' -tenant $TenantFilter
                return $Message
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to delete rules for $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            throw $Message
        }
    } else {
        # Only delete 1 rule
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-InboxRule' -Anchor $Username -cmdParams @{Identity = $RuleId }
            $Message = "Successfully deleted mailbox rule $($RuleName) for $($Username)"
            Write-LogMessage -headers $Headers -API $APIName -message "Deleted mailbox rule $($RuleName) for $($Username)" -Sev 'Info' -tenant $TenantFilter
            return $Message
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to delete rule for $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            throw $Message
        }
    }
}
