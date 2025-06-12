function New-CippAuditLogSearch {
    <#
    .SYNOPSIS
        Create a new audit log search
    .DESCRIPTION
        Create a new audit log search in Microsoft Graph Security API
    .PARAMETER DisplayName
        The display name of the audit log search. Default is 'CIPP Audit Search - ' + current date and time.
    .PARAMETER TenantFilter
        The tenant to filter on.
    .PARAMETER StartTime
        The start time to filter on.
    .PARAMETER EndTime
        The end time to filter on.
    .PARAMETER RecordTypeFilters
        The record types to filter on.
    .PARAMETER KeywordFilter
        The keyword to filter on.
    .PARAMETER ServiceFilter
        The service to filter on.
    .PARAMETER OperationsFilters
        The operations to filter on.
    .PARAMETER UserPrincipalNameFilters
        The user principal names to filter on.
    .PARAMETER IPAddressFilter
        The IP addresses to filter on.
    .PARAMETER ObjectIdFilters
        The object IDs to filter on.
    .PARAMETER AdministrativeUnitFilters
        The administrative units to filter on.
    .PARAMETER ProcessLogs
        Store the search in the CIPP AuditLogSearches table for alert processing.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$DisplayName = 'CIPP Audit Search - ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'),
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [datetime]$StartTime,
        [Parameter(Mandatory = $true)]
        [datetime]$EndTime,
        [Parameter()]
        [ValidateSet(
            'exchangeAdmin', 'exchangeItem', 'exchangeItemGroup', 'sharePoint', 'syntheticProbe', 'sharePointFileOperation',
            'oneDrive', 'azureActiveDirectory', 'azureActiveDirectoryAccountLogon', 'dataCenterSecurityCmdlet',
            'complianceDLPSharePoint', 'sway', 'complianceDLPExchange', 'sharePointSharingOperation',
            'azureActiveDirectoryStsLogon', 'skypeForBusinessPSTNUsage', 'skypeForBusinessUsersBlocked',
            'securityComplianceCenterEOPCmdlet', 'exchangeAggregatedOperation', 'powerBIAudit', 'crm', 'yammer',
            'skypeForBusinessCmdlets', 'discovery', 'microsoftTeams', 'threatIntelligence', 'mailSubmission',
            'microsoftFlow', 'aeD', 'microsoftStream', 'complianceDLPSharePointClassification', 'threatFinder',
            'project', 'sharePointListOperation', 'sharePointCommentOperation', 'dataGovernance', 'kaizala',
            'securityComplianceAlerts', 'threatIntelligenceUrl', 'securityComplianceInsights', 'mipLabel',
            'workplaceAnalytics', 'powerAppsApp', 'powerAppsPlan', 'threatIntelligenceAtpContent', 'labelContentExplorer',
            'teamsHealthcare', 'exchangeItemAggregated', 'hygieneEvent', 'dataInsightsRestApiAudit',
            'informationBarrierPolicyApplication', 'sharePointListItemOperation', 'sharePointContentTypeOperation',
            'sharePointFieldOperation', 'microsoftTeamsAdmin', 'hrSignal', 'microsoftTeamsDevice', 'microsoftTeamsAnalytics',
            'informationWorkerProtection', 'campaign', 'dlpEndpoint', 'airInvestigation', 'quarantine', 'microsoftForms',
            'applicationAudit', 'complianceSupervisionExchange', 'customerKeyServiceEncryption', 'officeNative',
            'mipAutoLabelSharePointItem', 'mipAutoLabelSharePointPolicyLocation', 'microsoftTeamsShifts', 'secureScore',
            'mipAutoLabelExchangeItem', 'cortanaBriefing', 'search', 'wdatpAlerts', 'powerPlatformAdminDlp',
            'powerPlatformAdminEnvironment', 'mdatpAudit', 'sensitivityLabelPolicyMatch', 'sensitivityLabelAction',
            'sensitivityLabeledFileAction', 'attackSim', 'airManualInvestigation', 'securityComplianceRBAC',
            'userTraining', 'airAdminActionInvestigation', 'mstic', 'physicalBadgingSignal', 'teamsEasyApprovals',
            'aipDiscover', 'aipSensitivityLabelAction', 'aipProtectionAction', 'aipFileDeleted', 'aipHeartBeat',
            'mcasAlerts', 'onPremisesFileShareScannerDlp', 'onPremisesSharePointScannerDlp', 'exchangeSearch',
            'sharePointSearch', 'privacyDataMinimization', 'labelAnalyticsAggregate', 'myAnalyticsSettings',
            'securityComplianceUserChange', 'complianceDLPExchangeClassification', 'complianceDLPEndpoint',
            'mipExactDataMatch', 'msdeResponseActions', 'msdeGeneralSettings', 'msdeIndicatorsSettings',
            'ms365DCustomDetection', 'msdeRolesSettings', 'mapgAlerts', 'mapgPolicy', 'mapgRemediation',
            'privacyRemediationAction', 'privacyDigestEmail', 'mipAutoLabelSimulationProgress',
            'mipAutoLabelSimulationCompletion', 'mipAutoLabelProgressFeedback', 'dlpSensitiveInformationType',
            'mipAutoLabelSimulationStatistics', 'largeContentMetadata', 'microsoft365Group', 'cdpMlInferencingResult',
            'filteringMailMetadata', 'cdpClassificationMailItem', 'cdpClassificationDocument', 'officeScriptsRunAction',
            'filteringPostMailDeliveryAction', 'cdpUnifiedFeedback', 'tenantAllowBlockList', 'consumptionResource',
            'healthcareSignal', 'dlpImportResult', 'cdpCompliancePolicyExecution', 'multiStageDisposition',
            'privacyDataMatch', 'filteringDocMetadata', 'filteringEmailFeatures', 'powerBIDlp', 'filteringUrlInfo',
            'filteringAttachmentInfo', 'coreReportingSettings', 'complianceConnector',
            'powerPlatformLockboxResourceAccessRequest', 'powerPlatformLockboxResourceCommand',
            'cdpPredictiveCodingLabel', 'cdpCompliancePolicyUserFeedback', 'webpageActivityEndpoint', 'omePortal',
            'cmImprovementActionChange', 'filteringUrlClick', 'mipLabelAnalyticsAuditRecord', 'filteringEntityEvent',
            'filteringRuleHits', 'filteringMailSubmission', 'labelExplorer', 'microsoftManagedServicePlatform',
            'powerPlatformServiceActivity', 'scorePlatformGenericAuditRecord', 'filteringTimeTravelDocMetadata', 'alert',
            'alertStatus', 'alertIncident', 'incidentStatus', 'case', 'caseInvestigation', 'recordsManagement',
            'privacyRemediation', 'dataShareOperation', 'cdpDlpSensitive', 'ehrConnector', 'filteringMailGradingResult',
            'publicFolder', 'privacyTenantAuditHistoryRecord', 'aipScannerDiscoverEvent', 'eduDataLakeDownloadOperation',
            'm365ComplianceConnector', 'microsoftGraphDataConnectOperation', 'microsoftPurview',
            'filteringEmailContentFeatures', 'powerPagesSite', 'powerAppsResource', 'plannerPlan', 'plannerCopyPlan',
            'plannerTask', 'plannerRoster', 'plannerPlanList', 'plannerTaskList', 'plannerTenantSettings',
            'projectForTheWebProject', 'projectForTheWebTask', 'projectForTheWebRoadmap', 'projectForTheWebRoadmapItem',
            'projectForTheWebProjectSettings', 'projectForTheWebRoadmapSettings', 'quarantineMetadata',
            'microsoftTodoAudit', 'timeTravelFilteringDocMetadata', 'teamsQuarantineMetadata',
            'sharePointAppPermissionOperation', 'microsoftTeamsSensitivityLabelAction', 'filteringTeamsMetadata',
            'filteringTeamsUrlInfo', 'filteringTeamsPostDeliveryAction', 'mdcAssessments',
            'mdcRegulatoryComplianceStandards', 'mdcRegulatoryComplianceControls', 'mdcRegulatoryComplianceAssessments',
            'mdcSecurityConnectors', 'mdaDataSecuritySignal', 'vivaGoals', 'filteringRuntimeInfo', 'attackSimAdmin',
            'microsoftGraphDataConnectConsent', 'filteringAtpDetonationInfo', 'privacyPortal', 'managedTenants',
            'unifiedSimulationMatchedItem', 'unifiedSimulationSummary', 'updateQuarantineMetadata', 'ms365DSuppressionRule',
            'purviewDataMapOperation', 'filteringUrlPostClickAction', 'irmUserDefinedDetectionSignal', 'teamsUpdates',
            'plannerRosterSensitivityLabel', 'ms365DIncident', 'filteringDelistingMetadata',
            'complianceDLPSharePointClassificationExtended', 'microsoftDefenderForIdentityAudit',
            'supervisoryReviewDayXInsight', 'defenderExpertsforXDRAdmin', 'cdpEdgeBlockedMessage', 'hostedRpa',
            'cdpContentExplorerAggregateRecord', 'cdpHygieneAttachmentInfo', 'cdpHygieneSummary',
            'cdpPostMailDeliveryAction', 'cdpEmailFeatures', 'cdpHygieneUrlInfo', 'cdpUrlClick',
            'cdpPackageManagerHygieneEvent', 'filteringDocScan', 'timeTravelFilteringDocScan', 'mapgOnboard'
        )]
        [string[]]$RecordTypeFilters,
        [Parameter()]
        [string]$KeywordFilters,
        [Parameter()]
        [string[]]$ServiceFilters,
        [Parameter()]
        [string[]]$OperationsFilters,
        [Parameter()]
        [string[]]$UserPrincipalNameFilters,
        [Parameter()]
        [string[]]$IPAddressFilters,
        [Parameter()]
        [string[]]$ObjectIdFilters,
        [Parameter()]
        [string[]]$AdministrativeUnitFilters,
        [Parameter()]
        [switch]$ProcessLogs
    )

    $SearchParams = @{
        displayName         = 'CIPP Audit Search - ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        filterStartDateTime = $StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
        filterEndDateTime   = $EndTime.AddHours(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
    }
    if ($OperationsFilters) {
        $SearchParams.operationsFilters = $OperationsFilters
    }
    if ($RecordTypeFilters) {
        $SearchParams.recordTypeFilters = @($RecordTypeFilters)
    }
    if ($KeywordFilters) {
        $SearchParams.keywordFilters = $KeywordFilters
    }
    if ($ServiceFilters) {
        $SearchParams.serviceFilters = $ServiceFilters
    }
    if ($UserPrincipalNameFilters) {
        $SearchParams.userPrincipalNameFilters = @($UserPrincipalNameFilters)
    }
    if ($IPAddressFilters) {
        $SearchParams.ipAddressFilters = @($IPAddressFilters)
    }
    if ($ObjectIdFilterss) {
        $SearchParams.objectIdFilters = @($ObjectIdFilters)
    }
    if ($AdministrativeUnitFilters) {
        $SearchParams.administrativeUnitFilters = @($AdministrativeUnitFilters)
    }

    if ($PSCmdlet.ShouldProcess('Create a new audit log search for tenant ' + $TenantFilter)) {
        $Query = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/security/auditLog/queries' -body ($SearchParams | ConvertTo-Json -Compress) -tenantid $TenantFilter -AsApp $true

        if ($ProcessLogs.IsPresent -and $Query.id) {
            $Entity = [PSCustomObject]@{
                PartitionKey = [string]'Search'
                RowKey       = [string]$Query.id
                Tenant       = [string]$TenantFilter
                DisplayName  = [string]$DisplayName
                StartTime    = [datetime]$StartTime.ToUniversalTime()
                EndTime      = [datetime]$EndTime.ToUniversalTime()
                Query        = [string]($Query | ConvertTo-Json -Compress)
                CippStatus   = [string]'Pending'
            }
            $Table = Get-CIPPTable -TableName 'AuditLogSearches'
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }
        return $Query
    }
}
