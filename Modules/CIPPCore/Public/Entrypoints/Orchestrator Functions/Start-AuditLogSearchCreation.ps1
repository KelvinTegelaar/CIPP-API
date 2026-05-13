function Start-AuditLogSearchCreation {
    <#
    .SYNOPSIS
    Start the Audit Log Searches

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $ConfigTable = Get-CippTable -TableName 'WebhookRules'
        $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'Webhookv2'" | ForEach-Object {
            $ConfigEntry = $_
            if (!$ConfigEntry.excludedTenants) {
                $ConfigEntry | Add-Member -MemberType NoteProperty -Name 'excludedTenants' -Value @() -Force
            } else {
                $ConfigEntry.excludedTenants = $ConfigEntry.excludedTenants | ConvertFrom-Json
            }
            $ConfigEntry.Tenants = $ConfigEntry.Tenants | ConvertFrom-Json
            $ConfigEntry
        }

        $TenantList = Get-Tenants -IncludeErrors
        $AuditDisabledTable = Get-CIPPTable -TableName 'AuditLogDisabledTenants'
        $DisabledAuditRows = @(Get-CIPPAzDataTableEntity @AuditDisabledTable -Filter "PartitionKey eq 'AuditDisabledTenant'")
        $CurrentUnixTime = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        $AuditDisabledTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $ExpiredDisabledRows = [System.Collections.Generic.List[object]]::new()

        foreach ($DisabledRow in $DisabledAuditRows) {
            [int64]$ExpiresAtUnix = 0
            if (($null -eq $DisabledRow.ExpiresAtUnix) -or (-not [int64]::TryParse([string]$DisabledRow.ExpiresAtUnix, [ref]$ExpiresAtUnix))) {
                $ExpiredDisabledRows.Add($DisabledRow)
                continue
            }

            if ($ExpiresAtUnix -le $CurrentUnixTime) {
                $ExpiredDisabledRows.Add($DisabledRow)
                continue
            }

            [void]$AuditDisabledTenants.Add([string]$DisabledRow.RowKey)
        }

        if ($ExpiredDisabledRows.Count -gt 0) {
            Remove-AzDataTableEntity @AuditDisabledTable -Entity $ExpiredDisabledRows -Force | Out-Null
        }

        # Round time down to nearest minute
        $Now = Get-Date
        $StartTime = ($Now.AddSeconds(-$Now.Seconds)).AddHours(-1)
        $EndTime = $Now.AddSeconds(-$Now.Seconds)

        # Pre-expand tenant groups once per config entry to avoid repeated calls per tenant
        foreach ($ConfigEntry in $ConfigEntries) {
            $ConfigEntry | Add-Member -MemberType NoteProperty -Name 'ExpandedTenants' -Value (Expand-CIPPTenantGroups -TenantFilter ($ConfigEntry.Tenants)).value -Force
        }

        Write-Information "Audit Logs: Building batch for $($TenantList.Count) tenants across $($ConfigEntries.Count) config entries"

        $SkippedAuditDisabledCount = 0

        $Batch = foreach ($Tenant in $TenantList) {
            if ($AuditDisabledTenants.Contains($Tenant.defaultDomainName) -or $AuditDisabledTenants.Contains([string]$Tenant.customerId)) {
                $SkippedAuditDisabledCount++
                continue
            }

            $TenantInConfig = $false
            foreach ($ConfigEntry in $ConfigEntries) {
                if ($ConfigEntry.excludedTenants.value -contains $Tenant.defaultDomainName) {
                    continue
                }
                if ($ConfigEntry.ExpandedTenants -contains $Tenant.defaultDomainName -or $ConfigEntry.ExpandedTenants -contains 'AllTenants') {
                    $TenantInConfig = $true
                    break
                }
            }

            if (!$TenantInConfig) {
                continue
            }

            [PSCustomObject]@{
                FunctionName = 'AuditLogSearchCreation'
                Tenant       = $Tenant | Select-Object defaultDomainName, customerId, displayName
                StartTime    = $StartTime
                EndTime      = $EndTime
            }
        }

        if ($SkippedAuditDisabledCount -gt 0) {
            Write-Information "Audit Logs: Skipped $SkippedAuditDisabledCount tenants due to cached AuditingDisabledTenant status"
        }

        if (($Batch | Measure-Object).Count -gt 0) {
            $InputObject = [PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = 'AuditLogSearchCreation'
                SkipLog          = $true
            }
            Start-CIPPOrchestrator -InputObject $InputObject
            Write-Information "Started Audit Log search creation orchestrator with $($Batch.Count) tenants"
        } else {
            Write-Information 'No tenants found for Audit Log search creation'
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error creating audit log searches' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
