function Remove-CIPPCalendarInvites {
    [CmdletBinding()]
    param(
        $UserID,
        $TenantFilter,
        $Username,
        $APIName = 'Remove Calendar Invites',
        $Headers
    )

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-CalendarEvents' -Anchor $Username -cmdParams @{Identity = $Username; QueryWindowInDays = 730 ; CancelOrganizedMeetings = $true ; Confirm = $false }
        $Result = "Successfully cancelled all calendar invites for $($Username)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
        return $Result

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to cancel calendar invites for $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
