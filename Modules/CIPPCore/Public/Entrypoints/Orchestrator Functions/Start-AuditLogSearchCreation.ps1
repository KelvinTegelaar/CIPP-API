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

        Write-Information 'Audit Logs: Creating new searches'

        $Batch = foreach ($Tenant in $TenantList) {
            Write-Information "Processing tenant $($Tenant.defaultDomainName) - $($Tenant.customerId)"
            $TenantInConfig = $false
            $MatchingConfigs = [System.Collections.Generic.List[object]]::new()
            foreach ($ConfigEntry in $ConfigEntries) {
                if ($ConfigEntry.excludedTenants.value -contains $Tenant.defaultDomainName) {
                    continue
                }
                $TenantsList = Expand-CIPPTenantGroups -TenantFilter ($ConfigEntry.Tenants)
                if ($TenantsList.value -contains $Tenant.defaultDomainName -or $TenantsList.value -contains 'AllTenants') {
                    $TenantInConfig = $true
                    $MatchingConfigs.Add($ConfigEntry)
                }
            }

            if (!$TenantInConfig) {
                Write-Information "Tenant $($Tenant.defaultDomainName) has no configured audit log rules, skipping search creation."
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
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            Write-Information "Started Audit Log search creation orchestratorwith $($Batch.Count) tenants"
        } else {
            Write-Information 'No tenants found for Audit Log search creation'
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error creating audit log searches' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
