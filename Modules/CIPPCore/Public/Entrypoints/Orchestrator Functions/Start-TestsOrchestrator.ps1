function Start-TestsOrchestrator {
    <#
    .SYNOPSIS
    Start the Tests Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-TestsOrchestrator', 'Starting Tests Orchestrator')) {
        Write-LogMessage -API 'Tests' -message 'Starting Tests Schedule' -sev Info
        Invoke-CIPPDBTestsRun -TenantFilter 'allTenants'
    }
}
