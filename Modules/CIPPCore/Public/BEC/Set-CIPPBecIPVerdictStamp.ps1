function Set-CIPPBecIPVerdictStamp {
    <#
    .SYNOPSIS
        Stamps each address's verdict onto the case rows that carry it.
    .DESCRIPTION
        Adds IPVerdict (Compromised, LikelyAttacker, Suspicious, Unknown, LikelyUser, Safe, Service) to
        every sign-in, change, sent-mail and mailbox-activity row whose address has a verdict, so the
        existing finding tables show which activity came from where. Rows are changed in place;
        a row whose address has no verdict gets none.
    .PARAMETER Results
        The case payload (or the draft of it) whose rows are stamped.
    .PARAMETER Verdicts
        The IP verdict rows (Get-CIPPBecIPVerdicts).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Results,
        [object[]]$Verdicts = @()
    )

    $ByIP = @{}
    foreach ($Row in @($Verdicts | Where-Object { $_ -and $_.IP })) { $ByIP[[string]$Row.IP] = [string]$Row.Verdict }
    if ($ByIP.Count -eq 0 -or -not $PSCmdlet.ShouldProcess('BEC case rows', 'Stamp IP verdicts')) { return }
    $Sections = @(
        @{ Name = 'SuspectUserSignIns'; Field = 'IPAddress' }
        @{ Name = 'NonInteractiveSignIns'; Field = 'IPAddress' }
        @{ Name = 'InboxRuleChanges'; Field = 'ClientIP' }
        @{ Name = 'MailboxPermissionChanges'; Field = 'ClientIP' }
        @{ Name = 'SafelistChanges'; Field = 'ClientIP' }
        @{ Name = 'SharingChanges'; Field = 'ClientIP' }
        @{ Name = 'TransportRuleChanges'; Field = 'ClientIP' }
        @{ Name = 'DirectoryAudits'; Field = 'ClientIP' }
        @{ Name = 'SentMessages'; Field = 'FromIP' }
        @{ Name = 'MailActivity'; Field = 'ClientIP' }
    )
    $HostOf = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($Section in $Sections) {
        foreach ($Row in @($Results.($Section.Name))) {
            if (-not $Row) { continue }
            $Raw = [string]$Row.($Section.Field)
            $IP = $HostOf[$Raw]
            if ($null -eq $IP) { $IP = [string](ConvertTo-CIPPBecHostAddress -Address $Raw); $HostOf[$Raw] = $IP }
            if ($IP -and $ByIP.ContainsKey($IP)) {
                $Properties = $Row.PSObject.Properties
                $Properties.Remove('IPVerdict')
                $Properties.Add([psnoteproperty]::new('IPVerdict', $ByIP[$IP]))
            }
        }
    }
}
