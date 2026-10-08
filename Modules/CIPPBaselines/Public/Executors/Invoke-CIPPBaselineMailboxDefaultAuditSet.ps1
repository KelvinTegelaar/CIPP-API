function Invoke-CIPPBaselineMailboxDefaultAuditSet {
    <#
    .SYNOPSIS
        Executor for MailboxDefaultAuditSet: resets each offending mailbox to the default audit set.
    .DESCRIPTION
        Mailbox audit settings must be written on the mailbox's own server, so each write is
        anchored to its mailbox; a system-mailbox-anchored $batch fails with
        CmdletProxyNotAvailableException for every mailbox hosted elsewhere.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)

    $Targets = @($Current.targets | Where-Object { $_.id })
    if ($Targets.Count -eq 0) { return }

    $Failures = [System.Collections.Generic.List[string]]::new()
    # ponytail: one request per mailbox; fine for the handful a tenant customises, slow on a first run over thousands
    foreach ($Target in $Targets) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{ Identity = $Target.id; DefaultAuditSet = @('Admin', 'Delegate', 'Owner') } -Anchor $Target.id
        } catch {
            $Failures.Add("$($Target.id) -> $($_.Exception.Message)")
        }
    }

    if ($Failures.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "MailboxDefaultAuditSet: $($Failures.Count) of $($Targets.Count) mailbox writes failed. $(($Failures | Select-Object -First 10) -join ' | ')" -Sev 'Warning'
    }
    if ($Failures.Count -ge $Targets.Count) {
        throw "MailboxDefaultAuditSet: all $($Targets.Count) writes failed. $($Failures[0])"
    }
}
