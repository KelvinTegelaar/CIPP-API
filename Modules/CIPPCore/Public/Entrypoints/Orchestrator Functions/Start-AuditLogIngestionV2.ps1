function Start-AuditLogIngestionV2 {
    <#
    .SYNOPSIS
        V2 audit-log ingestion timer. Drives both download and processing, decoupled so that pending
        logs are processed even when there is nothing new to download.
    .DESCRIPTION
        Runs offset 15 minutes from the creation timer and fans out two kinds of work:

          1. Download tenants - AuditLogCoverage rows in state 'Created' (a search was created and is
             awaiting download) and due (not in backoff). Each gets a per-tenant orchestrator:
                 Batch         = AuditLogDownloadV2  (download succeeded searches -> CacheWebhooks)
                 PostExecution = AuditLogProcessV2   (enqueue processing if any cache rows are pending)

          2. Process-only tenants - tenants that have rows sitting in CacheWebhooks (downloaded but
             not yet processed, e.g. left behind by a worker crash mid-processing) but no pending
             download. These get a processing orchestrator fanned out DIRECTLY, skipping the no-op
             download orchestration.

        This makes processing self-healing: a crashed/partial processing run is retried on the next
        cycle off the cache contents, not gated behind a fresh download.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Now = (Get-Date).ToUniversalTime()

        # --- Download tenants: searches awaiting download (State = Created, due) ---
        $Created = @(Get-CIPPAzDataTableEntity @Ledger -Filter "State eq 'Created'")
        $DueCreated = $Created | Where-Object { -not $_.NextAttemptUtc -or ([datetimeoffset]$_.NextAttemptUtc).UtcDateTime -le $Now }
        $DownloadTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Name in @($DueCreated | Group-Object PartitionKey | ForEach-Object { $_.Name })) {
            if ($Name) { [void]$DownloadTenants.Add([string]$Name) }
        }

        # --- Process-only tenants: rows pending in the webhook cache (downloaded, not yet processed) ---
        $CacheTable = Get-CippTable -TableName 'CacheWebhooks'
        $CacheRows = @(Get-CIPPAzDataTableEntity @CacheTable -Property @('PartitionKey', 'RowKey'))
        $CacheTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Name in @($CacheRows | Group-Object PartitionKey | ForEach-Object { $_.Name })) {
            if ($Name) { [void]$CacheTenants.Add([string]$Name) }
        }

        if ($DownloadTenants.Count -eq 0 -and $CacheTenants.Count -eq 0) {
            Write-Information 'AuditLogV2: nothing to download or process'
            return
        }

        # 1) Download tenants -> download + post-exec processing in one orchestration.
        foreach ($TenantFilter in $DownloadTenants) {
            if ($PSCmdlet.ShouldProcess($TenantFilter, 'Download + process audit logs')) {
                Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                        OrchestratorName = "AuditLogIngestV2-$TenantFilter"
                        Batch            = @([PSCustomObject]@{ FunctionName = 'AuditLogDownloadV2'; TenantFilter = $TenantFilter })
                        PostExecution    = @{ FunctionName = 'AuditLogProcessV2'; Parameters = @{ TenantFilter = $TenantFilter } }
                        SkipLog          = $true
                    })
            }
        }

        # 2) Process-only tenants (pending cache, no pending download) -> process directly.
        $ProcessOnlyCount = 0
        foreach ($TenantFilter in $CacheTenants) {
            if ($DownloadTenants.Contains($TenantFilter)) { continue }
            $ProcessOnlyCount++
            if ($PSCmdlet.ShouldProcess($TenantFilter, 'Process pending audit logs')) {
                Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                        OrchestratorName = "AuditLogProcessV2-$TenantFilter"
                        QueueFunction    = [PSCustomObject]@{ FunctionName = 'AuditLogProcessingBatchV2'; Parameters = @{ TenantFilter = $TenantFilter } }
                        SkipLog          = $true
                    })
            }
        }

        Write-Information "AuditLogV2: ingestion fan-out - $($DownloadTenants.Count) download tenant(s), $ProcessOnlyCount process-only tenant(s)"
    } catch {
        Write-LogMessage -API 'AuditLogV2' -message 'Error in audit log ingestion orchestrator (V2)' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ('AuditLogV2 ingestion error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
