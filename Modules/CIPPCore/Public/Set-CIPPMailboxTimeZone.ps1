function Set-CIPPMailboxTimeZone {
    <#
    .SYNOPSIS
        Set the time zone of a mailbox
    .DESCRIPTION
        Sets the mailbox regional configuration time zone and the calendar working hours time zone to the same Windows time zone ID, for example British Columbia Standard Time. Existing calendar items are not moved.
    #>
    [CmdletBinding()]
    param (
        $Headers,
        [Parameter(Mandatory = $true)]
        $UserID,
        $Username,
        [Parameter(Mandatory = $true)]
        [string]$TimeZone,
        $APIName = 'Mailbox Time Zone',
        $TenantFilter
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Username)) { $Username = $UserID }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxRegionalConfiguration' -cmdParams @{
            Identity = $UserID
            TimeZone = $TimeZone
        } -Anchor $Username
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxCalendarConfiguration' -cmdParams @{
            Identity             = $UserID
            WorkingHoursTimeZone = $TimeZone
        } -Anchor $Username

        $Result = "Set time zone for $Username to $TimeZone"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set time zone for $Username to $TimeZone. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
