function Invoke-ExecCalendarTimeZoneMigration {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .SYNOPSIS
        Move a mailbox and its calendar events to a new time zone
    .DESCRIPTION
        Sets the mailbox and working hours time zone, then runs Invoke-CalendarEventMigration so future meetings the mailbox organises keep their local time in the new zone, for example Pacific Standard Time to British Columbia Standard Time.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Mailbox ExchangeGuid
    $Identity = $Request.Body.Identity
    $Mailbox = $Request.Body.UPN ?? $Identity
    # Windows time zone ID the events are currently in, e.g. Pacific Standard Time
    $FromTimeZone = $Request.Body.FromTimeZone.value
    # Windows time zone ID to move the mailbox and events to, e.g. British Columbia Standard Time
    $ToTimeZone = $Request.Body.ToTimeZone.value

    if (-not $Identity -or -not $FromTimeZone -or -not $ToTimeZone) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Identity, FromTimeZone and ToTimeZone are required' } })
    }
    if ($FromTimeZone -eq $ToTimeZone) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'The current and new time zone must be different' } })
    }

    try {
        # Migrate first so a tenant or mailbox without the cmdlet is left unchanged
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Invoke-CalendarEventMigration' -cmdParams @{
            Identity              = $Identity
            FromWindowsTimeZoneId = $FromTimeZone
            ToWindowsTimeZoneId   = $ToTimeZone
            QueryWindowInDays     = 1825
            Confirm               = $false
        } -Anchor $Mailbox
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxRegionalConfiguration' -cmdParams @{ Identity = $Identity; TimeZone = $ToTimeZone } -Anchor $Mailbox
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxCalendarConfiguration' -cmdParams @{ Identity = $Identity; WorkingHoursTimeZone = $ToTimeZone } -Anchor $Mailbox
        $Result = "Moved $Mailbox to $ToTimeZone and migrated the meetings it organises from $FromTimeZone. Recurring meetings are not migrated by Microsoft yet and need updating in Outlook."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to move $Mailbox to $ToTimeZone. Error: $($ErrorMessage.NormalizedError)"
        if ($ErrorMessage.NormalizedError -match 'Cmdlet type is not supported|status code does not indicate success: 403') {
            $Result = "$Result This usually means Microsoft has not rolled calendar migration out to this tenant or mailbox yet. Run this again later; it is safe to repeat."
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
