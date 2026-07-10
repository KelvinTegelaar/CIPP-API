function Start-AuditLogSearchCreationV2 {
    <#
    .SYNOPSIS
        V2 audit-log search creation timer. Plans non-overlapping 60-minute windows per tenant in the
        AuditLogCoverage ledger and fans out creation only to tenants that owe a window or have a
        retry due.
    .DESCRIPTION
        Replaces Start-AuditLogSearchCreation. Tenant selection is unchanged (WebhookRules Webhookv2,
        minus excluded, minus auditing-disabled). The key differences:
          * Windows are clock-aligned, 60 minutes, NON-overlapping (tracked in AuditLogCoverage).
          * Failed creations are recorded as Planned/Retry ledger rows, so they are retried (and gaps
            backfilled) instead of being silently dropped.
          * "First check what tenants need searches created" - the timer scans the ledger once and
            only fans out per-tenant activities for tenants that owe a window or have a due retry.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        # --- Tenant selection (same source as V1) ---
        $ConfigTable = Get-CippTable -TableName 'WebhookRules'
        $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'Webhookv2'" | ForEach-Object {
            $ConfigEntry = $_
            if (!$ConfigEntry.excludedTenants) {
                $ConfigEntry | Add-Member -MemberType NoteProperty -Name 'excludedTenants' -Value @() -Force
            } else {
                $ConfigEntry.excludedTenants = $ConfigEntry.excludedTenants | ConvertFrom-Json
            }
            $ConfigEntry.Tenants = $ConfigEntry.Tenants | ConvertFrom-Json
            $ConfigEntry | Add-Member -MemberType NoteProperty -Name 'ExpandedTenants' -Value (Expand-CIPPTenantGroups -TenantFilter ($ConfigEntry.Tenants)).value -Force
            $ConfigEntry
        }
        if (($ConfigEntries | Measure-Object).Count -eq 0) {
            Write-Information 'AuditLogV2: no webhook rules defined; nothing to create'
            return
        }

        $TenantList = Get-Tenants -IncludeErrors

        # Auditing-disabled skip set (reuse existing table + expiry semantics)
        $AuditDisabledTable = Get-CIPPTable -TableName 'AuditLogDisabledTenants'
        $NowUnix = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        $AuditDisabledTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($DisabledRow in @(Get-CIPPAzDataTableEntity @AuditDisabledTable -Filter "PartitionKey eq 'AuditDisabledTenant'")) {
            [int64]$ExpiresAtUnix = 0
            if ([int64]::TryParse([string]$DisabledRow.ExpiresAtUnix, [ref]$ExpiresAtUnix) -and $ExpiresAtUnix -gt $NowUnix) {
                [void]$AuditDisabledTenants.Add([string]$DisabledRow.RowKey)
            }
        }

        $InScope = foreach ($Tenant in $TenantList) {
            if ($AuditDisabledTenants.Contains($Tenant.defaultDomainName) -or $AuditDisabledTenants.Contains([string]$Tenant.customerId)) { continue }
            $Match = $false
            foreach ($ConfigEntry in $ConfigEntries) {
                if ($ConfigEntry.excludedTenants.value -contains $Tenant.defaultDomainName) { continue }
                if ($ConfigEntry.ExpandedTenants -contains $Tenant.defaultDomainName -or $ConfigEntry.ExpandedTenants -contains 'AllTenants') { $Match = $true; break }
            }
            if ($Match) { $Tenant }
        }
        $InScope = @($InScope)
        if ($InScope.Count -eq 0) {
            Write-Information 'AuditLogV2: no in-scope tenants'
            return
        }

        # --- Scan ledger once, group by tenant ---
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        # Cover the reconciliation horizon (48h) plus slack so the fan-out check sees existing recon rows.
        $HorizonIso = (Get-Date).AddHours(-50).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $AllRows = Get-CIPPAzDataTableEntity @Ledger -Filter "Timestamp ge datetime'$HorizonIso'"
        $ByTenant = @{}
        foreach ($Row in $AllRows) {
            if (-not $ByTenant.ContainsKey($Row.PartitionKey)) { $ByTenant[$Row.PartitionKey] = [System.Collections.Generic.List[object]]::new() }
            $ByTenant[$Row.PartitionKey].Add($Row)
        }

        $Now = (Get-Date).ToUniversalTime()
        $Batch = foreach ($Tenant in $InScope) {
            $Rows = if ($ByTenant.ContainsKey($Tenant.defaultDomainName)) { $ByTenant[$Tenant.defaultDomainName] } else { @() }
            $Owed = Get-CippAuditLogPlannedWindows -ExistingRows $Rows -Now $Now
            $OwedRecon = Get-CippAuditLogReconciliationWindows -ExistingRows $Rows -Now $Now
            $DuePlanned = @($Rows | Where-Object { $_.State -eq 'Planned' -and (-not $_.NextAttemptUtc -or ([datetimeoffset]$_.NextAttemptUtc).UtcDateTime -le $Now) })
            if (($Owed.Count -gt 0) -or ($OwedRecon.Count -gt 0) -or ($DuePlanned.Count -gt 0)) {
                [PSCustomObject]@{
                    FunctionName = 'AuditLogSearchCreationV2'
                    TenantFilter = $Tenant.defaultDomainName
                    TenantId     = [string]$Tenant.customerId
                }
            }
        }
        $Batch = @($Batch)

        if ($Batch.Count -gt 0) {
            Write-Information "AuditLogV2: $($Batch.Count) tenant(s) need search creation"
            if ($PSCmdlet.ShouldProcess('Start-AuditLogSearchCreationV2', 'Create audit log searches')) {
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'AuditLogSearchCreationV2'
                    Batch            = @($Batch)
                    SkipLog          = $true
                }
                Start-CIPPOrchestrator -InputObject $InputObject
            }
        } else {
            Write-Information 'AuditLogV2: no tenants need searches this run'
        }

        # --- Best-effort retention: drop ledger rows older than 7 days (all states; active windows are < 26h old) ---
        try {
            $CutoffIso = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Stale = @(Get-CIPPAzDataTableEntity @Ledger -Filter "Timestamp le datetime'$CutoffIso'" -Property PartitionKey, RowKey)
            if ($Stale.Count -gt 0) {
                Remove-AzDataTableEntity @Ledger -Entity $Stale -Force
                Write-Information "AuditLogV2: cleaned $($Stale.Count) stale ledger row(s)"
            }
        } catch {
            Write-Information "AuditLogV2: ledger cleanup skipped - $($_.Exception.Message)"
        }
    } catch {
        Write-LogMessage -API 'AuditLogV2' -message 'Error creating audit log searches (V2)' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ('AuditLogV2 create error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
