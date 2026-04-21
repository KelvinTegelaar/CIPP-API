function Push-CIPPDBCacheData {
    <#
    .SYNOPSIS
        List cache collection tasks for a single tenant (Phase 1 of fan-out/fan-in)

    .DESCRIPTION
        Checks tenant license capabilities and returns a list of grouped cache collection work items.
        Each item represents one collection type (Graph, ExchangeConfig, ExchangeData, etc.) that
        will run all its cache functions sequentially within a single activity invocation.

        This grouped approach reduces activity count from ~50-67 per tenant down to ~2-6 per tenant,
        dramatically cutting orchestrator replay overhead and table storage I/O.

        Does NOT start sub-orchestrators. The returned items are aggregated by the PostExecution
        function (CIPPDBCacheApplyBatch) and executed in a single flat orchestrator.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)
    Write-Host "Building cache task list for tenant: $($Item.TenantFilter)"
    $TenantFilter = $Item.TenantFilter
    $QueueId = $Item.QueueId

    try {
        # Check tenant capabilities for license-specific features
        $IntuneCapable = $false
        try {
            $IntuneCapable = Test-CIPPStandardLicense -StandardName 'IntuneLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Intune license check failed: $($_.Exception.Message)" -sev Warning -LogData $ErrorMessage
        }

        $ConditionalAccessCapable = $false
        try {
            $ConditionalAccessCapable = Test-CIPPStandardLicense -StandardName 'ConditionalAccessLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2') -SkipLog
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Conditional Access license check failed: $($_.Exception.Message)" -sev Warning -LogData $ErrorMessage
        }

        $AzureADPremiumP2Capable = $false
        try {
            $AzureADPremiumP2Capable = Test-CIPPStandardLicense -StandardName 'AzureADPremiumP2LicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Azure AD Premium P2 license check failed: $($_.Exception.Message)" -sev Warning -LogData $ErrorMessage
        }

        $ExchangeCapable = $false
        try {
            $ExchangeCapable = Test-CIPPStandardLicense -StandardName 'ExchangeLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') -SkipLog
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Exchange license check failed: $($_.Exception.Message)" -sev Warning -LogData $ErrorMessage
        }

        $ComplianceCapable = $false
        try {
            $ComplianceCapable = Test-CIPPStandardLicense -StandardName 'ComplianceLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('RMS_S_PREMIUM', 'RMS_S_PREMIUM2', 'MIP_S_CLP1', 'MIP_S_CLP2') -SkipLog
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Compliance license check failed: $($_.Exception.Message)" -sev Warning -LogData $ErrorMessage
        }

        Write-Information "License capabilities for $TenantFilter - Intune: $IntuneCapable, CA: $ConditionalAccessCapable, P2: $AzureADPremiumP2Capable, Exchange: $ExchangeCapable, Compliance: $ComplianceCapable"

        # Build grouped collection tasks — one activity per license category instead of one per cache type
        $Tasks = [System.Collections.Generic.List[object]]::new()

        # CopilotUsage always runs — endpoints return empty when no Copilot licenses are in use
        $Tasks.Add(@{
                FunctionName   = 'ExecCIPPDBCache'
                CollectionType = 'CopilotUsage'
                TenantFilter   = $TenantFilter
                QueueId        = $QueueId
                QueueName      = "DB Cache CopilotUsage - $TenantFilter"
            })

        # Graph collection always runs (no special license needed) — 25 cache types in one activity
        $Tasks.Add(@{
                FunctionName   = 'ExecCIPPDBCache'
                CollectionType = 'Graph'
                TenantFilter   = $TenantFilter
                QueueId        = $QueueId
                QueueName      = "DB Cache Graph - $TenantFilter"
            })
        # MFAState runs as its own activity — it makes 6+ API calls, bulk group/role member
        # resolution, and O(users × policies) CPU work that can take minutes on large tenants
        $Tasks.Add(@{
                FunctionName = 'ExecCIPPDBCache'
                Name         = 'MFAState'
                TenantFilter = $TenantFilter
                QueueId      = $QueueId
                QueueName    = "DB Cache MFAState - $TenantFilter"
            })

        # Exchange collections — split into config (quick policy calls), data (usage reports), and mailboxes (heavy, spawns permission/rule child orchestrators)
        if ($ExchangeCapable) {
            $Tasks.Add(@{
                    FunctionName   = 'ExecCIPPDBCache'
                    CollectionType = 'ExchangeConfig'
                    TenantFilter   = $TenantFilter
                    QueueId        = $QueueId
                    QueueName      = "DB Cache ExchangeConfig - $TenantFilter"
                })
            $Tasks.Add(@{
                    FunctionName   = 'ExecCIPPDBCache'
                    CollectionType = 'ExchangeData'
                    TenantFilter   = $TenantFilter
                    QueueId        = $QueueId
                    QueueName      = "DB Cache ExchangeData - $TenantFilter"
                })
            # Mailboxes runs as its own activity — it's heavy (fetches all mailboxes) and spawns
            # child orchestrators for permission/calendar/rules batching that need their own time
            $Tasks.Add(@{
                    FunctionName = 'ExecCIPPDBCache'
                    Name         = 'Mailboxes'
                    TenantFilter = $TenantFilter
                    QueueId      = $QueueId
                    QueueName    = "DB Cache Mailboxes - $TenantFilter"
                })
        } else {
            Write-Host "Skipping Exchange Online data collection for $TenantFilter - no required license"
        }

        if ($ConditionalAccessCapable) {
            $Tasks.Add(@{
                    FunctionName   = 'ExecCIPPDBCache'
                    CollectionType = 'ConditionalAccess'
                    TenantFilter   = $TenantFilter
                    QueueId        = $QueueId
                    QueueName      = "DB Cache ConditionalAccess - $TenantFilter"
                })
        } else {
            Write-Host "Skipping Conditional Access data collection for $TenantFilter - no required license"
        }

        if ($AzureADPremiumP2Capable) {
            $Tasks.Add(@{
                    FunctionName   = 'ExecCIPPDBCache'
                    CollectionType = 'IdentityProtection'
                    TenantFilter   = $TenantFilter
                    QueueId        = $QueueId
                    QueueName      = "DB Cache IdentityProtection - $TenantFilter"
                })
        } else {
            Write-Host "Skipping Azure AD Premium P2 data collection for $TenantFilter - no required license"
        }

        if ($IntuneCapable) {
            $Tasks.Add(@{
                    FunctionName   = 'ExecCIPPDBCache'
                    CollectionType = 'Intune'
                    TenantFilter   = $TenantFilter
                    QueueId        = $QueueId
                    QueueName      = "DB Cache Intune - $TenantFilter"
                })
        } else {
            Write-Host "Skipping Intune data collection for $TenantFilter - no required license"
        }

        if ($ComplianceCapable) {
            $Tasks.Add(@{
                    FunctionName   = 'ExecCIPPDBCache'
                    CollectionType = 'Compliance'
                    TenantFilter   = $TenantFilter
                    QueueId        = $QueueId
                    QueueName      = "DB Cache Compliance - $TenantFilter"
                })
        } else {
            Write-Host "Skipping Compliance data collection for $TenantFilter - no required license"
        }

        Write-Information "Built $($Tasks.Count) grouped cache tasks for tenant $TenantFilter (down from individual per-type tasks)"

        # Return the task list — the PostExecution function will aggregate and start a flat orchestrator
        return @($Tasks)

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to build cache task list: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @()
    }
}
