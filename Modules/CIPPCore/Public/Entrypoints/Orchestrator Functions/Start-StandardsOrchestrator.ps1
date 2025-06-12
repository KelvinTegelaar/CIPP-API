function Start-StandardsOrchestrator {
    <#
    .SYNOPSIS
    Start the Standards Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-StandardsOrchestrator', 'Starting Standards Orchestrator')) {
        Write-LogMessage -API 'Standards' -message 'Starting Standards Schedule' -sev Info
        Invoke-CIPPStandardsRun -tenantfilter 'allTenants'
    }
}
