function Start-DriftStandardsOrchestrator {
    <#
    .SYNOPSIS
    Start the Drift Standards Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-DriftStandardsOrchestrator', 'Starting Drift Standards Orchestrator')) {
        Write-LogMessage -API 'Standards' -message 'Starting Drift Standards Schedule' -sev Info
        Invoke-CIPPStandardsRun -Drift
    }
}
