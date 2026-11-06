function Get-CIPPDBCacheSchedule {
    <#
    .SYNOPSIS
        What the nightly cache run collects, in run order, with the license preset each entry needs
    .DESCRIPTION
        An entry with Types is a collection group run by Invoke-CIPPDBCacheCollection; one without is a
        collector (Set-CIPPDBCache<Name>) run as its own task. License is a Test-CIPPStandardLicense preset.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()
    [ordered]@{
        CopilotUsage                     = @{
            Types = @(
                'CopilotUsageUserDetail'
                'CopilotUserCountSummary'
                'CopilotUserCountTrend'
                'CopilotReadinessActivity'
            )
        }
        Graph                            = @{
            Types = @(
                'Users'
                'Groups'
                'Guests'
                'ServicePrincipals'
                'Apps'
                'AppFederatedCredentials'
                'Devices'
                'Organization'
                'Roles'
                'RoleDefinitions'
                'RoleAssignments'
                'AdministrativeUnits'
                'AdminConsentRequestPolicy'
                'AuthorizationPolicy'
                'AuthenticationMethodsPolicy'
                'SecurityDefaults'
                'DirectoryRecommendations'
                'CrossTenantAccessPolicy'
                'DefaultAppManagementPolicy'
                'ActivityBasedTimeoutPolicy'
                'Settings'
                'SecureScore'
                'PIMSettings'
                'Domains'
                'B2BManagementPolicy'
                'DeviceRegistrationPolicy'
                'OAuth2PermissionGrants'
                'AppRoleAssignments'
                'LicenseOverview'
                'ActiveUserDetail'
                'M365AppUserDetail'
                'BitlockerKeys'
                'AdminReportSettings'
                'PeopleInsights'
                'Pronouns'
                'NamePronunciation'
                'PhotoUpdateSettings'
                'OrganizationBranding'
                'HomeRealmDiscoveryPolicy'
                'MobileDeviceManagementPolicies'
                'PermissionGrantPolicies'
                'CopilotAdminSettings'
                'CopilotPolicySettings'
                'SelfServicePurchaseProducts'
                'MoeraDmarc'
                'DomainAnalyser'
                'ServiceHealthOverviews'
                'ServiceHealthIssues'
                'MessageCenterMessages'
            )
        }
        MFAState                         = @{}
        ExchangeConfig                   = @{
            License = 'Exchange'
            Types   = @(
                'ExoAntiPhishPolicies'
                'ExoMalwareFilterPolicies'
                'ExoTransportRules'
                'ExoDkimSigningConfig'
                'ExoOrganizationConfig'
                'ExoAcceptedDomains'
                'ExoHostedContentFilterPolicy'
                'ExoHostedOutboundSpamFilterPolicy'
                'ExoQuarantinePolicy'
                'ExoRemoteDomain'
                'ExoSharingPolicy'
                'ExoAdminAuditLogConfig'
                'ExoPresetSecurityPolicy'
                'ExoTenantAllowBlockList'
                'ExoInboundConnector'
                'ExoProtectionAlert'
                'OwaMailboxPolicy'
                'ReportSubmissionPolicy'
                'ReportSubmissionRule'
                'ExoTransportConfig'
                'ExoHostedConnectionFilterPolicy'
                'ExoExternalInOutlook'
                'ExoOutboundConnector'
                'ExoRoleAssignmentPolicy'
                'ExoAppRoleAssignments'
                'ExoApplicationAccessPolicies'
                'ExoGlobalQuarantinePolicy'
                'ExoOMEConfiguration'
                'ExoIRMConfiguration'
                'ExoMailboxPlans'
                'ExoRetentionPolicyTags'
                'ExoRetentionPolicies'
                'ExoDynamicDistributionGroup'
                'ExoMailContacts'
                'ExoTenantAllowBlockListSpoofItems'
                'ExoPhishSimConfig'
            )
        }
        ExchangeData                     = @{
            License = 'Exchange'
            Types   = @(
                'CASMailboxes'
                'MailboxUsage'
                'MailTrafficSummary'
                'OfficeActivations'
                'HVEAccounts'
            )
        }
        Mailboxes                        = @{ License = 'Exchange' }
        ConditionalAccess                = @{
            License = 'Entra'
            Types   = @(
                'ConditionalAccessPolicies'
                'UserRegistrationDetails'
                'AppCredentialChanges'
                'ServicePrincipalRoleChanges'
                'DelegatedGrantChanges'
            )
        }
        ServicePrincipalSignInActivities = @{ License = 'Entra' }
        AppCredentialSignInActivities    = @{ License = 'Entra' }
        IdentityProtection               = @{
            License = 'EntraP2'
            Types   = @(
                'RiskyUsers'
                'RiskyServicePrincipals'
                'ServicePrincipalRiskDetections'
                'RiskDetections'
            )
        }
        PIM                              = @{
            License = 'PIM'
            Types   = @(
                'RoleEligibilitySchedules'
                'RoleAssignmentScheduleInstances'
                'RoleManagementPolicies'
            )
        }
        Intune                           = @{
            License = 'Intune'
            Types   = @(
                'ManagedDevices'
                'IntunePolicies'
                'IntuneApplications'
                'IntuneAssignmentFilters'
                'IntuneCompliancePolicies'
                'ManagedDeviceEncryptionStates'
                'IntuneAppProtectionPolicies'
                'IntuneScripts'
                'IntuneReusableSettings'
                'MDEOnboarding'
                'AutopilotDeploymentProfiles'
                'DeviceEnrollmentConfigurations'
                'IntuneDeviceManagementSettings'
                'IntuneDataProcessorOnboarding'
                'IntuneBrandingProfile'
                'ManagedDeviceCleanupRules'
                'DetectedApps'
                'IntuneAppInstallStatus'
                'IntuneNonCompliantSettings'
            )
        }
        Compliance                       = @{
            License = 'Compliance'
            Types   = @(
                'SensitivityLabels'
                'DlpCompliancePolicies'
                'ComplianceRetentionPolicies'
                'ComplianceRetentionRules'
                'ExoDlpSensitiveInfoTypes'
                'ExoLabels'
            )
        }
        Defender                         = @{
            License = 'DefenderForEndpoint'
            Types   = @(
                'DefenderCVEs'
            )
        }
        DefenderForOffice365             = @{
            License = 'DefenderForOffice365'
            Types   = @(
                'ExoSafeLinksPolicies'
                'ExoSafeAttachmentPolicies'
                'ExoAtpPolicyForO365'
                'ExoTeamsProtectionPolicy'
            )
        }
        SharePoint                       = @{
            License = 'SharePoint'
            Types   = @(
                'SPOTenant'
                'SharePointAdminSettings'
                'SharePointUsageReport'
                'SiteActivity'
                'OneDriveUsage'
            )
        }
        SPOSites                         = @{ License = 'SharePoint' }
        SharePointSiteUsage              = @{ License = 'SharePoint' }
        Teams                            = @{
            License = 'Teams'
            Types   = @(
                'CsTeamsMeetingPolicy'
                'CsTeamsClientConfiguration'
                'CsExternalAccessPolicy'
                'CsTenantFederationConfiguration'
                'CsTeamsMessagingPolicy'
                'CsTeamsFilesPolicy'
                'CsTeamsMessagingConfiguration'
                'CsTeamsAppPermissionPolicy'
                'Teams'
                'TeamsActivity'
                'TeamsVoice'
                'TeamsResourceAccounts'
            )
        }
    }
}
