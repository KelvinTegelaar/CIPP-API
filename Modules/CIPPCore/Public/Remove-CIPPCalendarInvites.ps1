function Remove-CIPPCalendarInvites {
    [CmdletBinding()]
    param(
        $userid,
        $tenantFilter,
        $username,
        $APIName = 'Remove Calendar Invites',
        $Headers
    )

    try {

        New-ExoRequest -tenantid $tenantFilter -cmdlet 'Remove-CalendarEvents' -Anchor $username -cmdParams @{Identity = $username; QueryWindowInDays = 730 ; CancelOrganizedMeetings = $true ; Confirm = $false }
        Write-LogMessage -headers $Headers -API $APIName -message "Cancelled all calendar invites for $($username)" -Sev 'Info' -tenant $tenantFilter
        "Cancelled all calendar invites for $($username)"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not cancel calendar invites for $($username): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $tenantFilter -LogData $ErrorMessage
        return "Could not cancel calendar invites for $($username). Error: $($ErrorMessage.NormalizedError)"
    }
}
