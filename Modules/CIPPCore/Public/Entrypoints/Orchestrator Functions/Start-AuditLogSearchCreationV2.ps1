function Start-AuditLogSearchCreationV2 {
    <#
    .SYNOPSIS
        V2 audit-log search creation timer. Plans non-overlapping 60-minute windows per tenant in the
        AuditLogCoverage ledger and fans out creation only to tenants that owe a window or have a
        retry due.
    .DESCRIPTION
        Replaces Start-AuditLogSearchCreation. Tenant selection is unchanged (WebhookRules Webhookv2,
        minus excluded, minus auditing-disabled). The key differences:
          * Windows are clock-aligned, 35 minutes on a 30-minute stride, so consecutive windows
            OVERLAP by 5 minutes (tracked in AuditLogCoverage). The overlap is deliberate - it
            covers records landing on a boundary - and is safe only because alerting de-duplicates
            by record id, which it does in exactly one place: the claim-insert into AuditLogs in
            Invoke-CippWebhookProcessing. Nothing downstream of that de-duplicates.
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
        $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'Webhookv2'" | Where-Object { $_.Disabled -ne $true } | ForEach-Object {
            $ConfigEntry = $_
            if (!$ConfigEntry.excludedTenants) {
                $ConfigEntry | Add-Member -MemberType NoteProperty -Name 'excludedTenants' -Value @() -Force
            } else {
                # Expand tenant groups in exclusions so group members match on defaultDomainName
                $Excluded = $ConfigEntry.excludedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue
                $ConfigEntry.excludedTenants = if ($Excluded) { @(Expand-CIPPTenantGroups -TenantFilter $Excluded) } else { @() }
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

        # Hoisted into hash sets once per rule, rather than an array -contains per tenant per rule.
        # -contains is a linear scan, so the original was tenants x rules x tenants-per-rule string
        # comparisons every cycle - at a few hundred tenants and a handful of AllTenants rules that
        # is millions of comparisons to answer a question that is a set membership test.
        # AllTenants is resolved once here too, since it does not depend on the tenant being tested.
        $RuleScopes = foreach ($ConfigEntry in $ConfigEntries) {
            $Included = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Name in @($ConfigEntry.ExpandedTenants)) {
                if ($Name) { [void]$Included.Add([string]$Name) }
            }
            $Excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Name in @($ConfigEntry.excludedTenants.value)) {
                if ($Name) { [void]$Excluded.Add([string]$Name) }
            }
            [PSCustomObject]@{
                Included   = $Included
                Excluded   = $Excluded
                AllTenants = $Included.Contains('AllTenants')
            }
        }
        $RuleScopes = @($RuleScopes)

        $InScope = foreach ($Tenant in $TenantList) {
            if ($AuditDisabledTenants.Contains($Tenant.defaultDomainName) -or $AuditDisabledTenants.Contains([string]$Tenant.customerId)) { continue }
            $Match = $false
            $DomainName = [string]$Tenant.defaultDomainName
            foreach ($Scope in $RuleScopes) {
                if ($Scope.Excluded.Contains($DomainName)) { continue }
                if ($Scope.AllTenants -or $Scope.Included.Contains($DomainName)) { $Match = $true; break }
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
        # Projected to the five columns actually consumed: PartitionKey to group by tenant, State
        # and NextAttemptUtc for the due-retry test below, and RowKey plus WindowStart for the two
        # window planners. Timestamp is not a key, so this is a cross-partition scan whatever the
        # predicate - what is controllable is how much comes back over the wire. At a few hundred
        # tenants this covers roughly 90 windows each across the 50-hour horizon, and it ran every
        # cycle pulling every column of every one of them.
        $AllRows = Get-CIPPAzDataTableEntity @Ledger -Filter "Timestamp ge datetime'$HorizonIso'" `
            -Property PartitionKey, RowKey, State, NextAttemptUtc, WindowStart
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
                Remove-CIPPAzDataTableEntity @Ledger -Entity $Stale -Force
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
