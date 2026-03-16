function Set-CIPPVacationOOO {
    param(
        [Parameter(Mandatory)] [string]$TenantFilter,
        [Parameter(Mandatory)] [ValidateSet('Add', 'Remove')] [string]$Action,
        [object[]]$Users,
        [string]$InternalMessage,
        [string]$ExternalMessage,
        [string]$APIName = 'OOO Vacation Mode',
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

    $Results = [System.Collections.Generic.List[string]]::new()

    foreach ($upn in $Users) {
        if ([string]::IsNullOrWhiteSpace($upn)) { continue }
        try {
            # Use Scheduled when StartTime/EndTime are provided (vacation always has dates),
            # otherwise fall back to Enabled for backwards compatibility with in-flight tasks
            $State = if ($Action -eq 'Add') {
                if ($PSBoundParameters.ContainsKey('StartTime') -and $PSBoundParameters.ContainsKey('EndTime')) { 'Scheduled' } else { 'Enabled' }
            } else { 'Disabled' }

            $SplatParams = @{
                UserID       = $upn
                TenantFilter = $TenantFilter
                State        = $State
                APIName      = $APIName
                Headers      = $Headers
            }

            if ($Action -eq 'Add') {
                # Pass start/end times when available
                if ($PSBoundParameters.ContainsKey('StartTime')) {
                    $SplatParams.StartTime = $StartTime
                }
                if ($PSBoundParameters.ContainsKey('EndTime')) {
                    $SplatParams.EndTime = $EndTime
                }

                # Only pass messages on Add — Remove only disables, preserving any messages
                # the user may have updated themselves during vacation
                if (-not [string]::IsNullOrWhiteSpace($InternalMessage)) {
                    $SplatParams.InternalMessage = $InternalMessage
                }
                if (-not [string]::IsNullOrWhiteSpace($ExternalMessage)) {
                    $SplatParams.ExternalMessage = $ExternalMessage
                }

                # Calendar options — pass through when explicitly provided
                if ($PSBoundParameters.ContainsKey('CreateOOFEvent')) {
                    $SplatParams.CreateOOFEvent = $CreateOOFEvent
                }
                if ($PSBoundParameters.ContainsKey('OOFEventSubject')) {
                    $SplatParams.OOFEventSubject = $OOFEventSubject
                }
                if ($PSBoundParameters.ContainsKey('AutoDeclineFutureRequestsWhenOOF')) {
                    $SplatParams.AutoDeclineFutureRequestsWhenOOF = $AutoDeclineFutureRequestsWhenOOF
                }
                if ($PSBoundParameters.ContainsKey('DeclineEventsForScheduledOOF')) {
                    $SplatParams.DeclineEventsForScheduledOOF = $DeclineEventsForScheduledOOF
                }
                if ($PSBoundParameters.ContainsKey('DeclineAllEventsForScheduledOOF')) {
                    $SplatParams.DeclineAllEventsForScheduledOOF = $DeclineAllEventsForScheduledOOF
                }
                if ($PSBoundParameters.ContainsKey('DeclineMeetingMessage')) {
                    $SplatParams.DeclineMeetingMessage = $DeclineMeetingMessage
                }
            }
            $result = Set-CIPPOutOfOffice @SplatParams
            $Results.Add($result)
        } catch {
            $err = (Get-CippException -Exception $_).NormalizedError
            $Results.Add("Failed to set OOO for ${upn}: $err")
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed OOO for ${upn}: $err" -Sev Error
        }
    }
    return $Results
}
