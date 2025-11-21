function Push-AuditLogSearchCreation {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param($Item)

    # Get params from batch item
    $Tenant = $Item.Tenant
    $StartTime = $Item.StartTime
    $EndTime = $Item.EndTime
    $ServiceFilters = @($Item.ServiceFilters)

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
        if ($PSCmdlet.ShouldProcess('Push-AuditLogSearchCreation', 'Creating Audit Log Search')) {
            $NewSearch = New-CippAuditLogSearch @LogSearch
            Write-Information "Created audit log search $($Tenant.defaultDomainName) - $($NewSearch.displayName)"
        }
    } catch {
        Write-Information "Error creating audit log search $($Tenant.defaultDomainName) - $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }
    return $true
}
