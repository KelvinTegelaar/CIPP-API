function Get-CIPPStatsBaselines {
    <#
    .SYNOPSIS
    Baseline usage counts for the anonymous stats payload
    #>
    [CmdletBinding()]
    param()

    try {
        $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
        $BaselineCount = @(Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout'" -Property RowKey).Count

        # One delta row exists per (standard, scope, stage); scopes are tenants, groups or AllTenants.
        $DeltaTable = Get-CippTable -tablename 'Baselines'
        $Deltas = @(Get-CIPPAzDataTableEntity @DeltaTable -Filter "PartitionKey eq 'standardItem'" -Property standardName, scope, scopeId)

        $Scopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Standards = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Delta in $Deltas) {
            if ($Delta.scopeId) { [void]$Scopes.Add("$($Delta.scopeId)") }
            # Multi-instance keys look like 'standard#instance'; count the standard once.
            if ($Delta.standardName) { [void]$Standards.Add(("$($Delta.standardName)" -split '#')[0]) }
        }

        [PSCustomObject]@{
            BaselineCount          = $BaselineCount
            BaselineTenantCount    = $Scopes.Count
            BaselineStandardsCount = $Standards.Count
        }
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate baseline stats: $($_.Exception.Message)" -sev Warning
        [PSCustomObject]@{ BaselineCount = $null; BaselineTenantCount = $null; BaselineStandardsCount = $null }
    }
}
