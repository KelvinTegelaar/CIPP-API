function Invoke-CIPPScheduledNinjaCveSync {
    <#
    .SYNOPSIS
        Queues NinjaOne CVE sync for all mapped tenants via the NinjaOne orchestrator.
    .DESCRIPTION
        Builds a batch of per-tenant CveSyncTenant work items and submits them to the
        NinjaOneOrchestrator for fan-out execution. Each tenant runs as its own durable
        activity, avoiding the Azure Functions 10-minute timeout risk of a sequential loop.
    #>
    [CmdletBinding()]
    param()

    try {
        $CIPPMapping      = Get-CIPPTable -TableName CippMapping
        $Filter           = "PartitionKey eq 'NinjaOneMapping'"
        $TenantsToProcess = Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.IntegrationId -and $_.IntegrationId -ne '' }

        if (-not $TenantsToProcess) {
            Write-LogMessage -API 'NinjaCveSync' -message 'No tenants mapped in NinjaOne — nothing to sync' -sev 'Warning'
            return
        }

        $Batch = foreach ($Tenant in $TenantsToProcess) {
            [PSCustomObject]@{
                NinjaAction  = 'CveSyncTenant'
                MappedTenant = $Tenant
                FunctionName = 'NinjaOneQueue'
            }
        }

        if (($Batch | Measure-Object).Count -gt 0) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'NinjaOneOrchestrator'
                Batch            = @($Batch)
            }
            $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
            Write-LogMessage -API 'NinjaCveSync' -message "NinjaOne CVE sync queued for $(($TenantsToProcess | Measure-Object).Count) tenant(s). Instance: '$InstanceId'" -sev 'Info'
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'NinjaCveSync' -message "Failed to queue NinjaOne CVE sync: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
    }
}
