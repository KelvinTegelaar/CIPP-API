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
        Write-LogMessage -API 'Standards' -message 'Starting Standards Schedule' -sev Info
        New-CIPPStandardsRun -tenantfilter 'allTenants'
    }
}
