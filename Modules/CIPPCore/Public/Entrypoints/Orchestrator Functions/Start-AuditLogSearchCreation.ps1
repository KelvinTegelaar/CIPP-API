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
        # Round time down to nearest minute
        $Now = Get-Date
        $StartTime = ($Now.AddSeconds(-$Now.Seconds)).AddHours(-1)
        $EndTime = $Now.AddSeconds(-$Now.Seconds)

        # Pre-expand tenant groups once per config entry to avoid repeated calls per tenant
        foreach ($ConfigEntry in $ConfigEntries) {
            $ConfigEntry | Add-Member -MemberType NoteProperty -Name 'ExpandedTenants' -Value (Expand-CIPPTenantGroups -TenantFilter ($ConfigEntry.Tenants)).value -Force
        }

        Write-Information "Audit Logs: Building batch for $($TenantList.Count) tenants across $($ConfigEntries.Count) config entries"

        $Batch = foreach ($Tenant in $TenantList) {
            $TenantInConfig = $false
            $MatchingConfigs = [System.Collections.Generic.List[object]]::new()
            foreach ($ConfigEntry in $ConfigEntries) {
                if ($ConfigEntry.excludedTenants.value -contains $Tenant.defaultDomainName) {
                    continue
                }
                if ($ConfigEntry.ExpandedTenants -contains $Tenant.defaultDomainName -or $ConfigEntry.ExpandedTenants -contains 'AllTenants') {
                    $TenantInConfig = $true
                    $MatchingConfigs.Add($ConfigEntry)
                }
            }

            if (!$TenantInConfig) {
                continue
            }

            if ($MatchingConfigs) {
                [PSCustomObject]@{
                    FunctionName   = 'AuditLogSearchCreation'
                    Tenant         = $Tenant | Select-Object defaultDomainName, customerId, displayName
                    StartTime      = $StartTime
                    EndTime        = $EndTime
                    ServiceFilters = @($MatchingConfigs | Select-Object -Property type | Sort-Object -Property type -Unique | ForEach-Object { $_.type.split('.')[1] })
                }
            }
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
