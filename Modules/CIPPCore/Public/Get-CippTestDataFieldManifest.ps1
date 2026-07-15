function Get-CippTestDataFieldManifest {
    <#
    .SYNOPSIS
        Per-type field manifest for Get-CIPPTestData projection.

    .DESCRIPTION
        Returns the union of top-level fields that every consumer of a given CippReportingDB type
        reads, or $null for types that must be fetched whole.

        ADDING OR CHANGING A FIELD READ IN A TEST? ADD IT HERE FIRST. Get-CIPPTestData only
        materializes what is listed here; reading an unlisted field returns $null with no error,
        and the test emits a wrong compliance verdict silently.

        Rules for editing this table:

        * Top-level names only. Projection is record-level: a kept field keeps its ENTIRE subtree.
          For `$policy.conditions.users.includeRoles` you add 'conditions' — never 'users'.
        * When in doubt, add it. Over-inclusion costs a little memory; omission corrupts results.
        * Matching is case-insensitive, and tests rely on it — some read a field using different
          casing than the stored JSON. Use the real JSON casing here; do not "fix" the test.
        * A type absent from this table is fetched whole — the safe default. A new type, or a
          field nobody listed, degrades to pre-projection behaviour rather than corrupting a
          verdict. Deliberately absent are types whose tests discover column names at runtime by
          reflecting over the record, and types small enough that projecting buys nothing.
        * Verify with a verdict diff across more than one tenant — see Get-CIPPTestData .NOTES.
          "0 errored" proves nothing; the failure mode is silent.

        CONSUMERS THAT ARE NOT TEST FILES — easy to miss, since no test names these fields:

          Get-CippDbRole ......... Roles
          Get-CippDbRoleMembers .. RoleAssignmentScheduleInstances, RoleEligibilitySchedules,
                                   Roles — including the 'principal' subtree, which no test
                                   mentions; omitting it blanks every role member across the
                                   privileged-access tests
          Test-E8AsrRule ......... IntuneConfigurationPolicies — the field contract for the E8 ASR
                                   tests, which read nothing themselves

        Any new helper calling Get-CIPPTestData belongs on that list.

        WHY PER-TYPE, NOT PER-CALL-SITE: the field set is part of the Get-CIPPTestData cache key,
        so per-caller lists fragment the cache — the same rows parsed once per distinct list, all
        alive together for the TTL. Many call sites share few types, and they mostly want the same
        large subtrees, so fragmenting measured several times worse than one shared entry.

    .PARAMETER Type
        The CippReportingDB data type.

    .OUTPUTS
        [string[]] of field names, or $null meaning "no projection — return every field".

    .EXAMPLE
        Get-CippTestDataFieldManifest -Type 'Users'
        Callers do not normally invoke this — Get-CIPPTestData consults it automatically by type.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Type
    )

    if ([string]::IsNullOrWhiteSpace($Type)) { return $null }

    if (-not $script:CippTestDataFieldManifest) {
        # Deliberately ABSENT (=> fetched whole), do not "helpfully" add them:
        #   CopilotUsageUserDetail, CopilotUserCountSummary, CopilotUserCountTrend — their tests
        #     discover column names at runtime by reflecting over the record, so no field list
        #     can be known ahead of time (CopilotReady015/016/017).
        #   ExoGlobalQuarantinePolicy — ORCA107 annotates the record via `Select-Object *`, and
        #     the type is tiny, so projecting buys nothing.
        $script:CippTestDataFieldManifest = @{
            'AdminConsentRequestPolicy'          = @('isEnabled', 'reviewers', 'notifyReviewers', 'remindersEnabled', 'requestDurationInDays')
            'Apps'                               = @('id', 'appId', 'displayName', 'keyCredentials', 'passwordCredentials', 'signInAudience', 'servicePrincipalLockConfiguration', 'owners', 'web', 'spa', 'publicClient')
            'AppsAndServices'                    = @('id', 'isOfficeStoreEnabled', 'isAppAndServicesTrialEnabled')
            'AuthenticationFlowsPolicy'          = @('selfServiceSignUp')
            'AuthenticationMethodsPolicy'        = @('authenticationMethodConfigurations', 'policyMigrationState', 'reportSuspiciousActivitySettings', 'systemCredentialPreferences')
            'AuthenticationStrengths'            = @('id', 'displayName', 'policyType', 'allowedCombinations')
            'AuthorizationPolicy'                = @('defaultUserRolePermissions', 'guestUserRoleId', 'allowInvitesFrom', 'allowedToUseSSPR', 'allowedToSignUpEmailBasedSubscriptions', 'allowEmailVerifiedUsersToJoinOrganization', 'permissionGrantPolicyIdsAssignedToDefaultUserRole', 'allowUserConsentForRiskyApps', 'allowedToCreateTenants')
            'B2BManagementPolicy'                = @('allowInvitesFrom', 'invitationsAllowedAndBlockedDomainsPolicy', 'definition')
            'CASMailbox'                         = @('Identity', 'DisplayName', 'SmtpClientAuthenticationDisabled')
            'ConditionalAccessPolicies'          = @('id', 'displayName', 'state', 'conditions', 'grantControls', 'sessionControls', 'createdDateTime', 'modifiedDateTime')
            'CopilotReadinessActivity'           = @('userPrincipalName', 'usesOutlookEmail', 'usesTeamsMeetings', 'usesTeamsChat', 'usesOfficeDocs', 'onQualifiedUpdateChannel', 'hasCopilotLicenseAssigned')
            'CrossTenantAccessPolicy'            = @('id', 'b2bCollaborationOutbound', 'b2bDirectConnectOutbound', 'tenantRestrictions')
            'CsExternalAccessPolicy'             = @('EnableFederationAccess', 'EnableTeamsConsumerAccess')
            'CsTeamsAppPermissionPolicy'         = @('Identity', 'GlobalCatalogAppsType', 'DefaultCatalogAppsType')
            'CsTeamsClientConfiguration'         = @('AllowDropbox', 'AllowBox', 'AllowGoogleDrive', 'AllowShareFile', 'AllowEgnyte', 'AllowEmailIntoChannel')
            'CsTeamsMeetingPolicy'               = @('AllowAnonymousUsersToJoinMeeting', 'AllowAnonymousUsersToStartMeeting', 'AutoAdmittedUsers', 'AllowPSTNUsersToBypassLobby', 'MeetingChatEnabledType', 'DesignatedPresenterRoleMode', 'AllowExternalParticipantGiveRequestControl', 'AllowExternalNonTrustedMeetingChat', 'AllowCloudRecording')
            'CsTeamsMessagingPolicy'             = @('UseB2BInvitesToAddExternalUsers', 'AllowSecurityEndUserReporting')
            'CsTenantFederationConfiguration'    = @('AllowFederatedUsers', 'AllowedDomains', 'AllowTeamsConsumer')
            'DefaultAppManagementPolicy'         = @('isEnabled', 'applicationRestrictions', 'servicePrincipalRestrictions')
            'DeviceRegistrationPolicy'           = @('azureADJoin', 'userDeviceQuota', 'localAdminPassword', 'multiFactorAuthConfiguration')
            'DeviceSettings'                     = @('secureByDefault')
            'DirectoryRecommendations'           = @('status', 'priority', 'displayName', 'impactType', 'lastModifiedDateTime', 'insights', 'recommendationType', 'applicationDisplayName', 'applicationId')
            'DlpCompliancePolicies'              = @('Name', 'DisplayName', 'Mode', 'Enabled', 'TeamsLocation', 'TeamsLocationException', 'Workload', 'EnforcementPlanes')
            'Domains'                            = @('id', 'passwordValidityPeriodInDays', 'authenticationType')
            'ExoAcceptedDomains'                 = @('DomainName', 'DomainType', 'SendingFromDomainDisabled')
            'ExoAdminAuditLogConfig'             = @('UnifiedAuditLogIngestionEnabled', 'AdminAuditLogEnabled')
            'ExoAntiPhishPolicies'               = @('Name', 'Identity', 'Enabled', 'PhishThresholdLevel', 'EnableMailboxIntelligence', 'EnableMailboxIntelligenceProtection', 'EnableSpoofIntelligence', 'TargetedUserProtectionAction', 'TargetedDomainProtectionAction', 'MailboxIntelligenceProtectionAction', 'AuthenticationFailAction', 'EnableFirstContactSafetyTips', 'EnableSimilarUsersSafetyTips', 'EnableSimilarDomainsSafetyTips', 'EnableUnusualCharactersSafetyTips', 'EnableUnauthenticatedSender', 'ExcludedSenders', 'ExcludedDomains', 'RecipientDomainIs', 'HonorDmarcPolicy')
            'ExoAtpPolicyForO365'                = @('EnableATPForSPOTeamsODB', 'EnableSafeDocs', 'AllowSafeDocsOpen')
            'ExoDkimSigningConfig'               = @('Domain', 'Enabled', 'Selector1CNAME', 'Selector2CNAME')
            'ExoHostedContentFilterPolicy'       = @('Name', 'Identity', 'AllowedSenders', 'AllowedSenderDomains', 'EnableSafeList', 'SpamAction', 'HighConfidenceSpamAction', 'BulkSpamAction', 'PhishSpamAction', 'HighConfidencePhishAction', 'RecipientDomainIs', 'BulkThreshold', 'MarkAsSpamBulkMail', 'QuarantineRetentionPeriod', 'InlineSafetyTipsEnabled', 'IPAllowList', 'PhishZapEnabled', 'SpamZapEnabled',
                'IncreaseScoreWithImageLinks', 'IncreaseScoreWithNumericIps', 'IncreaseScoreWithRedirectToOtherPort', 'IncreaseScoreWithBizOrInfoUrls', 'MarkAsSpamEmptyMessages', 'MarkAsSpamJavaScriptInHtml', 'MarkAsSpamFramesInHtml', 'MarkAsSpamObjectTagsInHtml', 'MarkAsSpamEmbedTagsInHtml', 'MarkAsSpamFormTagsInHtml', 'MarkAsSpamWebBugsInHtml', 'MarkAsSpamSensitiveWordList', 'MarkAsSpamFromAddressAuthFail', 'MarkAsSpamNdrBackscatter', 'MarkAsSpamSpfRecordHardFail')
            'ExoHostedOutboundSpamFilterPolicy'  = @('Identity', 'IsDefault', 'RecipientLimitExternalPerHour', 'RecipientLimitInternalPerHour', 'RecipientLimitPerDay', 'ActionWhenThresholdReached', 'NotifyOutboundSpam', 'NotifyOutboundSpamRecipients', 'BccSuspiciousOutboundMail', 'BccSuspiciousOutboundAdditionalRecipients', 'AutoForwardingMode')
            'ExoInboundConnector'                = @('Identity', 'Enabled', 'SenderDomains', 'EFSkipLastIP', 'EFSkipIPs', 'EFTestMode', 'EFUsers')
            'ExoMalwareFilterPolicies'           = @('Name', 'Identity', 'IsDefault', 'EnableFileFilter', 'FileTypes', 'EnableInternalSenderAdminNotifications', 'InternalSenderAdminAddress', 'ZapEnabled', 'Action', 'RecipientDomainIs')
            'ExoOrganizationConfig'              = @('CustomerLockBoxEnabled', 'BookingsEnabled', 'AuditDisabled', 'ExternalInOutlookEnabled', 'ExternalInOutlook', 'OAuth2ClientProfileEnabled', 'MailTipsAllTipsEnabled', 'MailTipsExternalRecipientsTipsEnabled', 'MailTipsGroupMetricsEnabled', 'MailTipsLargeAudienceThreshold', 'RejectDirectSend')
            'ExoPresetSecurityPolicy'            = @('Identity', 'State', 'ImpersonationProtectionState', 'EnableMailboxIntelligence', 'EnableMailboxIntelligenceProtection', 'EnableSimilarUsersSafetyTips', 'EnableSimilarDomainsSafetyTips', 'EnableUnusualCharactersSafetyTips')
            'ExoProtectionAlert'                 = @('Name', 'Disabled')
            'ExoRemoteDomain'                    = @('Name', 'DomainName', 'AutoForwardEnabled')
            'ExoSafeAttachmentPolicies'          = @('Name', 'Identity', 'Enable', 'Action', 'RecipientDomainIs')
            'ExoSafeLinksPolicies'               = @('Name', 'Identity', 'EnableSafeLinksForEmail', 'EnableSafeLinksForTeams', 'EnableSafeLinksForOffice', 'TrackClicks', 'TrackUserClicks', 'AllowClickThrough', 'ScanUrls', 'EnableForInternalSenders', 'DeliverMessageAfterScan', 'DisableUrlRewrite', 'RecipientDomainIs', 'IsBuiltInProtection')
            'ExoSharingPolicy'                   = @('Name', 'Enabled', 'Domains')
            'ExoTenantAllowBlockList'            = @('Action', 'ListType', 'Value')
            'ExoTransportConfig'                 = @('SmtpClientAuthenticationDisabled')
            'ExoTransportRules'                  = @('Name', 'State', 'Priority', 'SetSCL', 'SetSpamConfidenceLevel', 'SetHeaderName', 'SetHeaderValue', 'SenderDomainIs')
            'FormsSettings'                      = @('isInOrgFormsPhishingScanEnabled')
            'Groups'                             = @('id', 'displayName', 'mail', 'visibility', 'groupTypes', 'members', 'isAssignableToRole')
            'Guests'                             = @('id', 'displayName', 'userPrincipalName', 'accountEnabled', 'signInActivity', 'createdDateTime', 'sponsors')
            # URLName is added by the collector (Add-Member), not returned by Graph. It carries the
            # Graph resource each policy came from (iosManagedAppProtection /
            # androidManagedAppProtection / targetedManagedAppConfiguration) and is the only
            # platform discriminator on these records — @odata.type is not preserved in the cache.
            'IntuneAppProtectionManagedAppPolicies' = @('URLName', 'displayName', 'assignments')
            'IntuneConfigurationPolicies'        = @('name', 'platforms', 'technologies', 'templateReference', 'settings', 'assignments')
            'IntuneDeviceCompliancePolicies'     = @('@odata.type', 'displayName', 'assignments', 'osMinimumVersion', 'bitLockerEnabled', 'storageRequireEncryption')
            'IntuneDeviceConfigurations'         = @('@odata.type', 'displayName', 'assignments', 'qualityUpdatesDeferralPeriodInDays', 'fileVaultEnabled', 'wiFiSecurityType')
            'IntuneDeviceEnrollmentConfigurations' = @('@odata.type', 'displayName', 'priority', 'deviceEnrollmentConfigurationType', 'assignments', 'androidForWorkRestriction', 'androidRestriction', 'iosRestriction', 'macOSRestriction', 'windowsRestriction')
            'LicenseOverview'                    = @('License', 'TotalLicenses', 'CountUsed', 'ServicePlans', 'AssignedUsers', 'TermInfo')
            'Mailboxes'                          = @('UPN', 'UserPrincipalName', 'displayName', 'recipientTypeDetails', 'ExternalDirectoryObjectId', 'AuditEnabled', 'AuditOwner', 'AuditBypassEnabled', 'WhenSoftDeleted', 'LitigationHoldEnabled', 'LicensedForLitigationHold', 'ComplianceTagHoldApplied', 'RetentionPolicy', 'InPlaceHolds')
            'ManagedDevices'                     = @('deviceName', 'lastSyncDateTime', 'operatingSystem', 'osVersion')
            'MDEOnboarding'                      = @('partnerState')
            'MFAState'                           = @('UPN', 'userPrincipalName', 'DisplayName', 'AccountEnabled', 'UserType', 'IsAdmin', 'isLicensed', 'PerUser', 'PerUserMFAState', 'CoveredByCA', 'CoveredBySD', 'MFARegistration', 'MFACapable', 'MFAMethods')
            'NamedLocations'                     = @('@odata.type', 'displayName', 'isTrusted')
            'OfficeActivations'                  = @('userPrincipalName', 'userActivationCounts')
            'Organization'                       = @('onPremisesSyncEnabled', 'onPremisesLastSyncDateTime')
            'OwaMailboxPolicy'                   = @('Identity', 'IsDefault', 'PersonalAccountsEnabled', 'PersonalAccountCalendarsEnabled', 'AdditionalStorageProvidersAvailable')
            'ReportSubmissionPolicy'             = @('ReportJunkToCustomizedAddress', 'ReportPhishToCustomizedAddress', 'ReportChatMessageEnabled', 'ReportChatMessageToCustomizedAddressEnabled')
            'RiskDetections'                     = @('riskState', 'riskLevel', 'riskEventType', 'riskDetail', 'userPrincipalName', 'userDisplayName', 'detectedDateTime', 'activityDateTime')
            'RiskyServicePrincipals'             = @('id', 'appId', 'displayName', 'servicePrincipalType', 'riskState', 'riskLevel', 'riskLastUpdatedDateTime')
            'RiskyUsers'                         = @('id', 'userPrincipalName', 'riskState', 'riskLevel', 'riskDetail', 'riskLastUpdatedDateTime')
            # 'principal' is NOT read by any test file — Get-CippDbRoleMembers reads
            # $member.principal.displayName/.userPrincipalName. Omitting it would silently blank
            # every role member across the CIS/E8/ZTNA privileged-access tests.
            'RoleAssignmentScheduleInstances'    = @('roleDefinitionId', 'assignmentType', 'memberType', 'endDateTime', 'principalId', 'principal')
            'RoleEligibilitySchedules'           = @('roleDefinitionId', 'principalId', 'principal', 'scheduleInfo')
            # policyId, not id: this type is sourced from roleManagementPolicyAssignments (only the
            # assignment carries roleDefinitionId) and the policy is flattened up one level.
            'RoleManagementPolicies'             = @('policyId', 'scopeId', 'scopeType', 'roleDefinitionId', 'rules', 'effectiveRules')
            'Roles'                              = @('id', 'displayName', 'roleTemplateId', 'members')
            'SecureScore'                        = @('currentScore', 'maxScore', 'createdDateTime', 'controlScores')
            'SensitivityLabels'                  = @('name', 'PolicyName', 'IsValid', 'isActive', 'sensitivity', 'parent', 'hasProtection')
            'ServicePrincipalRiskDetections'     = @('servicePrincipalId', 'servicePrincipalDisplayName', 'appId', 'activity', 'riskState', 'riskLevel', 'riskEventType', 'detectedDateTime', 'lastUpdatedDateTime')
            'ServicePrincipals'                  = @('id', 'appId', 'displayName', 'accountEnabled', 'keyCredentials', 'passwordCredentials', 'appOwnerOrganizationId', 'servicePrincipalType', 'replyUrls', 'owners', 'appRoleAssignmentRequired', 'preferredSingleSignOnMode')
            'Settings'                           = @('id', 'templateId', 'displayName', 'values', 'isOfficeStoreEnabled', 'isAppAndServicesTrialEnabled', 'isInOrgFormsPhishingScanEnabled')
            'SPOTenant'                          = @('LegacyAuthProtocolsEnabled', 'EnableAzureADB2BIntegration', 'SharingCapability', 'OneDriveSharingCapability', 'PreventExternalUsersFromResharing', 'SharingDomainRestrictionMode', 'SharingAllowedDomainList', 'SharingBlockedDomainList', 'DefaultSharingLinkType', 'DefaultLinkPermission', 'ExternalUserExpirationRequired', 'ExternalUserExpireInDays', 'EmailAttestationRequired', 'EmailAttestationReAuthDays', 'DisallowInfectedFileDownload')
            'UserRegistrationDetails'            = @('id', 'userPrincipalName', 'userDisplayName', 'isMfaCapable', 'isMfaRegistered', 'methodsRegistered')
            'Users'                              = @('id', 'userPrincipalName', 'displayName', 'accountEnabled', 'userType', 'onPremisesSyncEnabled', 'assignedLicenses', 'assignedPlans', 'signInActivity', 'passwordPolicies')
        }
    }

    return $script:CippTestDataFieldManifest[$Type]
}
