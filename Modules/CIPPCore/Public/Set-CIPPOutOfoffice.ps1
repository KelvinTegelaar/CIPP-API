function Set-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserID,
        $InternalMessage,
        $ExternalMessage,
        $TenantFilter,
        [ValidateSet('Enabled', 'Disabled', 'Scheduled')]
        [Parameter(Mandatory = $true)]
        [string]$State,
        $APIName = 'Set Out of Office',
        $Headers,
        $StartTime,
        $EndTime,
        [bool]$CreateOOFEvent,
        [string]$OOFEventSubject,
        [bool]$AutoDeclineFutureRequestsWhenOOF,
        [bool]$DeclineEventsForScheduledOOF,
        [bool]$DeclineAllEventsForScheduledOOF,
        [string]$DeclineMeetingMessage
    )

    try {

        $CmdParams = @{
            Identity         = $UserID
            AutoReplyState   = $State
            ExternalAudience = 'None'
        }

        if ($PSBoundParameters.ContainsKey('InternalMessage')) {
            $CmdParams.InternalMessage = $InternalMessage
        }

        if ($PSBoundParameters.ContainsKey('ExternalMessage')) {
            $CmdParams.ExternalMessage = $ExternalMessage
            $CmdParams.ExternalAudience = 'All'
        }

        if ($State -eq 'Scheduled') {
            # If starttime or endtime are not provided, default to enabling OOO for 7 days
            $StartTime = $StartTime ? $StartTime : (Get-Date).ToString()
            $EndTime = $EndTime ? $EndTime : (Get-Date $StartTime).AddDays(7)
            $CmdParams.StartTime = $StartTime
            $CmdParams.EndTime = $EndTime

            # Calendar options — only included when explicitly provided
            if ($PSBoundParameters.ContainsKey('CreateOOFEvent')) {
                $CmdParams.CreateOOFEvent = $CreateOOFEvent
            }
            if ($PSBoundParameters.ContainsKey('OOFEventSubject')) {
                $CmdParams.OOFEventSubject = $OOFEventSubject
            }
            if ($PSBoundParameters.ContainsKey('AutoDeclineFutureRequestsWhenOOF')) {
                $CmdParams.AutoDeclineFutureRequestsWhenOOF = $AutoDeclineFutureRequestsWhenOOF
            }
            if ($PSBoundParameters.ContainsKey('DeclineEventsForScheduledOOF')) {
                $CmdParams.DeclineEventsForScheduledOOF = $DeclineEventsForScheduledOOF
            }
            if ($PSBoundParameters.ContainsKey('DeclineAllEventsForScheduledOOF')) {
                $CmdParams.DeclineAllEventsForScheduledOOF = $DeclineAllEventsForScheduledOOF
            }
            if ($PSBoundParameters.ContainsKey('DeclineMeetingMessage')) {
                $CmdParams.DeclineMeetingMessage = $DeclineMeetingMessage
            }
        }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxAutoReplyConfiguration' -cmdParams $CmdParams -Anchor $UserID

        $Results = $State -eq 'Scheduled' ?
        "Scheduled Out-of-office for $($UserID) between $($StartTime.toString()) and $($EndTime.toString())" :
        "Set Out-of-office for $($UserID) to $State."

        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Info' -tenant $TenantFilter
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not add OOO for $($UserID). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Results
    }
}
