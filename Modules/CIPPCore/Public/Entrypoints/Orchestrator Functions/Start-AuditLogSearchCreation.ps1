function Start-AuditLogSearchCreation {
    <#
    .SYNOPSIS
    Start the Audit Log Searches
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $ConfigTable = Get-CippTable -TableName 'WebhookRules'
        $ConfigEntries = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'Webhookv2'" | ForEach-Object {
            $ConfigEntry = $_
            $ConfigEntry.excludedTenants = $ConfigEntry.excludedTenants | ConvertFrom-Json
            $ConfigEntry.Tenants = $ConfigEntry.Tenants | ConvertFrom-Json
            $ConfigEntry
        }

        $TenantList = Get-Tenants -IncludeErrors
        # Round time down to nearest minute
        $Now = Get-Date
        $StartTime = ($Now.AddSeconds(-$Now.Seconds)).AddHours(-1)
        $EndTime = $Now.AddSeconds(-$Now.Seconds)

        Write-Information 'Audit Logs: Creating new searches'

        foreach ($Tenant in $TenantList) {
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
                $ServiceFilters = $MatchingConfigs | Select-Object -Property type | Sort-Object -Property type -Unique | ForEach-Object { $_.type.split('.')[1] }
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
                    if ($PSCmdlet.ShouldProcess('Start-AuditLogSearchCreation', 'Creating Audit Log Search')) {
                        $NewSearch = New-CippAuditLogSearch @LogSearch
                        Write-Information "Created audit log search $($Tenant.defaultDomainName) - $($NewSearch.displayName)"
                    }
                } catch {
                    Write-Information "Error creating audit log search $($Tenant.defaultDomainName) - $($_.Exception.Message)"
                }
            }
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error creating audit log searches' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
