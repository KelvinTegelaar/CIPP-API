function Remove-CIPPCalendarInvites {
    [CmdletBinding()]
    param(
        $userid,
        $tenantFilter,
        $username,
        $APIName = 'Remove Calendar Invites',
        $ExecutingUser
    )

    try {
        
        New-ExoRequest -tenantid $tenantFilter -cmdlet 'Remove-CalendarEvents' -Anchor $username -cmdParams @{Identity = $username; QueryWindowInDays = 730 ; CancelOrganizedMeetings = $true ; Confirm = $false} 
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Cancelled all calendar invites for $($username)" -Sev 'Info' -tenant $tenantFilter
        "Cancelled all calendar invites for $($username)" 

    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not cancel calendar invites for $($username): $($_.Exception.Message)" -Sev 'Error' -tenant $tenantFilter
        return "Could not cancel calendar invites for $($username). Error: $($_.Exception.Message)"
    }
}
