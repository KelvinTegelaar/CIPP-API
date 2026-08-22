function Start-StandardsOrchestrator {
    <#
    .SYNOPSIS
    Start the Standards Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-StandardsOrchestrator', 'Starting Standards Orchestrator')) {
        # Baselines replaces the classic engine: while the flag is enabled the scheduled
        # classic run is a no-op, so the two systems never remediate against each other.
        $BaselinesFlag = $(try { Get-CIPPFeatureFlag -Id 'Baselines' } catch { $null })
        if ($BaselinesFlag.Enabled -eq $true) {
            Write-LogMessage -API 'Standards' -message 'Skipped the scheduled classic standards run: the Baselines feature is enabled and replaces it.' -sev Info
            return
        }
        Write-LogMessage -API 'Standards' -message 'Starting Standards Schedule' -sev Info
        New-CIPPStandardsRun -tenantfilter 'allTenants'
    }
}
