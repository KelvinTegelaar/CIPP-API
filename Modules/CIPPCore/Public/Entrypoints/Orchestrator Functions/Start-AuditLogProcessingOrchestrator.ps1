function Start-AuditLogProcessingOrchestrator {
    <#
    .SYNOPSIS
    Start the Audit Log Processing Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param()
    Write-Information 'Starting audit log processing orchestrator'
    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'AuditLogTenantProcess'
        QueueFunction    = [PSCustomObject]@{
            FunctionName = 'AuditLogProcessingBatch'
        }
        SkipLog          = $true
    }
    Start-CIPPOrchestrator -InputObject $InputObject
    Write-Information 'Audit log processing orchestrator started'
}
