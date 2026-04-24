function Start-TestsOrchestrator {
    <#
    .SYNOPSIS
    Start the Tests Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    if ($PSCmdlet.ShouldProcess('Start-TestsOrchestrator', "Starting Tests Orchestrator for $TenantFilter")) {
        try {
            Write-LogMessage -API 'Tests' -tenant $TenantFilter -message 'Starting Tests Schedule' -sev Info
            return Start-CIPPDBTestsRun -TenantFilter $TenantFilter -Force:$Force
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to start tests orchestrator: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            throw
        }
    }
}
