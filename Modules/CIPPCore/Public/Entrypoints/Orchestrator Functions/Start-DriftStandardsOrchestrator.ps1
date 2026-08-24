function Start-DriftStandardsOrchestrator {
    <#
    .SYNOPSIS
    Start the Drift Standards Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-DriftStandardsOrchestrator', 'Starting Drift Standards Orchestrator')) {
        # Baselines replaces the classic engine: while the flag is enabled the scheduled
        # classic drift run is a no-op, so the two systems never fight over the same tenants.
        $BaselinesFlag = $(try { Get-CIPPFeatureFlag -Id 'Baselines' } catch { $null })
        if ($BaselinesFlag.Enabled -eq $true) {
            Write-LogMessage -API 'Standards' -message 'Skipped the scheduled classic drift run: the Baselines feature is enabled and replaces it.' -sev Info
            return
        }
        Write-LogMessage -API 'Standards' -message 'Starting Drift Standards Schedule' -sev Info
        New-CIPPStandardsRun -Drift
    }
}
