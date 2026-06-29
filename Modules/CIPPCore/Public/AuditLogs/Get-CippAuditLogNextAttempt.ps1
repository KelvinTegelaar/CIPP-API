function Get-CippAuditLogNextAttempt {
    <#
    .SYNOPSIS
        Compute the next-attempt UTC time for a retried audit-log coverage row (exponential backoff).
    .DESCRIPTION
        Used by the V2 audit-log pipeline to schedule retries of failed search creations and
        downloads in the AuditLogCoverage ledger. Exponential backoff with jitter, capped. Because
        the timers run every 15 minutes, small delays effectively mean "retry next run"; larger ones
        defer a persistently failing window before it is eventually dead-lettered by the caller.
    .PARAMETER Attempts
        The attempt count that has just been consumed (1 = first failure).
    .OUTPUTS
        [datetime] (UTC) when the row becomes eligible to retry.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [int]$Attempts,
        [int]$BaseMinutes = 5,
        [int]$CapMinutes = 240
    )
    $exp = [Math]::Max(0, $Attempts - 1)
    $delay = [Math]::Min($BaseMinutes * [Math]::Pow(2, $exp), $CapMinutes)
    $jitter = Get-Random -Minimum 0.8 -Maximum 1.2
    return (Get-Date).ToUniversalTime().AddMinutes($delay * $jitter)
}
