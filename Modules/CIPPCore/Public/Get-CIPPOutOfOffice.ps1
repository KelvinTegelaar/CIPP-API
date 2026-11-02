function Get-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        $UserID,
        $TenantFilter,
        $APIName = 'Get Out of Office',
        $Headers
    )

    try {
        $OutOfOffice = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxAutoReplyConfiguration' -cmdParams @{Identity = $UserID } -Anchor $UserID
        $Results = @{
            AutoReplyState                  = $OutOfOffice.AutoReplyState
            # Emit UTC with an explicit 'Z' marker. Get-MailboxAutoReplyConfiguration returns these
            # as server-local DateTimes; without the marker the browser reparses the wall-clock in its
            # own timezone, shifting a reopened schedule by the UTC offset (and drifting on re-save).
            StartTime                       = $OutOfOffice.StartTime ? $OutOfOffice.StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') : $null
            EndTime                         = $OutOfOffice.EndTime ? $OutOfOffice.EndTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') : $null
            InternalMessage                 = $OutOfOffice.InternalMessage
            ExternalMessage                 = $OutOfOffice.ExternalMessage
            CreateOOFEvent                  = $OutOfOffice.CreateOOFEvent
            OOFEventSubject                 = $OutOfOffice.OOFEventSubject
            AutoDeclineFutureRequestsWhenOOF = $OutOfOffice.AutoDeclineFutureRequestsWhenOOF
            DeclineEventsForScheduledOOF    = $OutOfOffice.DeclineEventsForScheduledOOF
            DeclineAllEventsForScheduledOOF = $OutOfOffice.DeclineAllEventsForScheduledOOF
            DeclineMeetingMessage           = $OutOfOffice.DeclineMeetingMessage
        } | ConvertTo-Json
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not retrieve out of office message for $($UserID). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        throw $Results
    }
}
