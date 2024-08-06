function Set-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        $userid,
        $InternalMessage,
        $ExternalMessage,
        $TenantFilter,
        $State,
        $APIName = 'Set Out of Office',
        $ExecutingUser,
        $StartTime,
        $EndTime
    )

    try {
        if (-not $StartTime) {
            $StartTime = (Get-Date).ToString()
        }
        if (-not $EndTime) {
            $EndTime = (Get-Date $StartTime).AddDays(7)
        }
        if ($State -ne 'Scheduled') {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxAutoReplyConfiguration' -cmdParams @{Identity = $userid; AutoReplyState = $State; InternalMessage = $InternalMessage; ExternalMessage = $ExternalMessage } -Anchor $userid
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Set Out-of-office for $($userid) to $state" -Sev 'Info' -tenant $TenantFilter
            return "Set Out-of-office for $($userid) to $state."
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxAutoReplyConfiguration' -cmdParams @{Identity = $userid; AutoReplyState = $State; InternalMessage = $InternalMessage; ExternalMessage = $ExternalMessage; StartTime = $StartTime; EndTime = $EndTime } -Anchor $userid
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Scheduled Out-of-office for $($userid) between $StartTime and $EndTime" -Sev 'Info' -tenant $TenantFilter
            return "Scheduled Out-of-office for $($userid) between $($StartTime.toString()) and $($EndTime.toString())"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add OOO for $($userid). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not add out of office message for $($userid). Error: $($ErrorMessage.NormalizedError)"
    }
}
