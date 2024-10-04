function Start-AuditLogOrchestrator {
    <#
    .SYNOPSIS
    Start the Audit Log Polling Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $AuditLogSearchesTable = Get-CIPPTable -TableName 'AuditLogSearches'
        $AuditLogSearches = Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "CippStatus eq 'Pending'"

        $ConfigTable = Get-CippTable -TableName 'WebhookRules'
        $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable

        $TenantList = Get-Tenants -IncludeErrors
        # Round time down to nearest minute
        $Now = Get-Date
        $StartTime = ($Now.AddSeconds(-$Now.Seconds)).AddHours(-1)
        $EndTime = $Now.AddSeconds(-$Now.Seconds)

        if (($AuditLogSearches | Measure-Object).Count -eq 0) {
            Write-Information 'No audit log searches available'
        } else {
            $Queue = New-CippQueueEntry -Name 'Audit Log Collection' -Reference 'AuditLogCollection' -TotalTasks ($AuditLogSearches).Count
            $Batch = $AuditLogSearches | Sort-Object -Property Tenant -Unique | Select-Object @{Name = 'TenantFilter'; Expression = { $_.Tenant } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'AuditLogTenant' } }

            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'AuditLogs'
                Batch            = @($Batch)
                SkipLog          = $true
            }
            if ($PSCmdlet.ShouldProcess('Start-AuditLogOrchestrator', 'Starting Audit Log Polling')) {
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            }
        }

        Write-Information 'Audit Logs: Creating new searches'
        foreach ($Tenant in $TenantList) {
            $Configuration = $ConfigEntries | Where-Object { ($_.Tenants -match $TenantFilter -or $_.Tenants -match 'AllTenants') }
            if ($Configuration) {
                $ServiceFilters = $Configuration | Select-Object -Property type | Sort-Object -Property type -Unique | ForEach-Object { $_.type.split('.')[1] }
                try {
                    $LogSearch = @{
                        StartTime         = $StartTime
                        EndTime           = $EndTime
                        ServiceFilters    = $ServiceFilters
                        TenantFilter      = $Tenant.defaultDomainName
                        ProcessLogs       = $true
                        RecordTypeFilters = @(
                            'exchangeAdmin', 'azureActiveDirectory', 'azureActiveDirectoryAccountLogon', 'dataCenterSecurityCmdlet',
                            'complianceDLPSharePoint', 'complianceDLPExchange', 'azureActiveDirectoryStsLogon', 'skypeForBusinessPSTNUsage',
                            'skypeForBusinessUsersBlocked', 'securityComplianceCenterEOPCmdlet', 'microsoftFlow', 'aeD', 'microsoftStream',
                            'threatFinder', 'project', 'dataGovernance', 'securityComplianceAlerts', 'threatIntelligenceUrl',
                            'securityComplianceInsights', 'mipLabel', 'workplaceAnalytics', 'powerAppsApp', 'powerAppsPlan',
                            'threatIntelligenceAtpContent', 'labelContentExplorer', 'hygieneEvent',
                            'dataInsightsRestApiAudit', 'informationBarrierPolicyApplication', 'microsoftTeamsAdmin', 'hrSignal',
                            'informationWorkerProtection', 'campaign', 'dlpEndpoint', 'airInvestigation', 'quarantine', 'microsoftForms',
                            'applicationAudit', 'complianceSupervisionExchange', 'customerKeyServiceEncryption', 'officeNative',
                            'mipAutoLabelSharePointItem', 'mipAutoLabelSharePointPolicyLocation', 'secureScore',
                            'mipAutoLabelExchangeItem', 'cortanaBriefing', 'search', 'wdatpAlerts', 'powerPlatformAdminDlp',
                            'powerPlatformAdminEnvironment', 'mdatpAudit', 'sensitivityLabelPolicyMatch', 'sensitivityLabelAction',
                            'sensitivityLabeledFileAction', 'attackSim', 'airManualInvestigation', 'securityComplianceRBAC', 'userTraining',
                            'airAdminActionInvestigation', 'mstic', 'physicalBadgingSignal', 'aipDiscover', 'aipSensitivityLabelAction',
                            'aipProtectionAction', 'aipFileDeleted', 'aipHeartBeat', 'mcasAlerts', 'onPremisesFileShareScannerDlp',
                            'onPremisesSharePointScannerDlp', 'exchangeSearch', 'privacyDataMinimization', 'labelAnalyticsAggregate',
                            'myAnalyticsSettings', 'securityComplianceUserChange', 'complianceDLPExchangeClassification',
                            'complianceDLPEndpoint', 'mipExactDataMatch', 'msdeResponseActions', 'msdeGeneralSettings', 'msdeIndicatorsSettings',
                            'ms365DCustomDetection', 'msdeRolesSettings', 'mapgAlerts', 'mapgPolicy', 'mapgRemediation',
                            'privacyRemediationAction', 'privacyDigestEmail', 'mipAutoLabelSimulationProgress', 'mipAutoLabelSimulationCompletion',
                            'mipAutoLabelProgressFeedback', 'dlpSensitiveInformationType', 'mipAutoLabelSimulationStatistics',
                            'largeContentMetadata', 'microsoft365Group', 'cdpMlInferencingResult', 'filteringMailMetadata',
                            'cdpClassificationMailItem', 'cdpClassificationDocument', 'officeScriptsRunAction', 'filteringPostMailDeliveryAction',
                            'cdpUnifiedFeedback', 'tenantAllowBlockList', 'consumptionResource', 'healthcareSignal', 'dlpImportResult',
                            'cdpCompliancePolicyExecution', 'multiStageDisposition', 'privacyDataMatch', 'filteringDocMetadata',
                            'filteringEmailFeatures', 'powerBIDlp', 'filteringUrlInfo', 'filteringAttachmentInfo', 'coreReportingSettings',
                            'complianceConnector', 'powerPlatformLockboxResourceAccessRequest', 'powerPlatformLockboxResourceCommand',
                            'cdpPredictiveCodingLabel', 'cdpCompliancePolicyUserFeedback', 'webpageActivityEndpoint', 'omePortal',
                            'cmImprovementActionChange', 'filteringUrlClick', 'mipLabelAnalyticsAuditRecord', 'filteringEntityEvent',
                            'filteringRuleHits', 'filteringMailSubmission', 'labelExplorer', 'microsoftManagedServicePlatform',
                            'powerPlatformServiceActivity', 'scorePlatformGenericAuditRecord', 'filteringTimeTravelDocMetadata', 'alert',
                            'alertStatus', 'alertIncident', 'incidentStatus', 'case', 'caseInvestigation', 'recordsManagement',
                            'privacyRemediation', 'dataShareOperation', 'cdpDlpSensitive', 'ehrConnector', 'filteringMailGradingResult',
                            'microsoftTodoAudit', 'timeTravelFilteringDocMetadata', 'microsoftDefenderForIdentityAudit',
                            'supervisoryReviewDayXInsight', 'defenderExpertsforXDRAdmin', 'cdpEdgeBlockedMessage', 'hostedRpa',
                            'cdpContentExplorerAggregateRecord', 'cdpHygieneAttachmentInfo', 'cdpHygieneSummary', 'cdpPostMailDeliveryAction',
                            'cdpEmailFeatures', 'cdpHygieneUrlInfo', 'cdpUrlClick', 'cdpPackageManagerHygieneEvent', 'filteringDocScan',
                            'timeTravelFilteringDocScan', 'mapgOnboard'
                        )
                    }
                    $NewSearch = New-CippAuditLogSearch @LogSearch
                    Write-Information "Created audit log search $($Tenant.defaultDomainName) - $($NewSearch.displayName)"
                } catch {
                    Write-Information "Error creating audit log search $($Tenant.defaultDomainName) - $($_.Exception.Message)"
                }
            }
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error processing audit logs' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
