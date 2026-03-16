function Push-CIPPDBCacheData {
    <#
    .SYNOPSIS
        List cache collection tasks for a single tenant (Phase 1 of fan-out/fan-in)

    .DESCRIPTION
        Checks tenant license capabilities and returns a list of cache collection work items.
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
        $IntuneCapable = Test-CIPPStandardLicense -StandardName 'IntuneLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog
        $ConditionalAccessCapable = Test-CIPPStandardLicense -StandardName 'ConditionalAccessLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2') -SkipLog
        $AzureADPremiumP2Capable = Test-CIPPStandardLicense -StandardName 'AzureADPremiumP2LicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog
        $ExchangeCapable = Test-CIPPStandardLicense -StandardName 'ExchangeLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') -SkipLog

        Write-Information "License capabilities for $TenantFilter - Intune: $IntuneCapable, CA: $ConditionalAccessCapable, P2: $AzureADPremiumP2Capable, Exchange: $ExchangeCapable"

        # Build list of cache collection tasks based on license capabilities
        $Tasks = [System.Collections.Generic.List[object]]::new()

        #region All Licenses - Basic tenant data collection
        $BasicCacheFunctions = @(
            'Users'
            'Groups'
            'Guests'
            'ServicePrincipals'
            'Apps'
            'Devices'
            'Organization'
            'Roles'
            'AdminConsentRequestPolicy'
            'AuthorizationPolicy'
            'AuthenticationMethodsPolicy'
            'DeviceSettings'
            'DirectoryRecommendations'
            'CrossTenantAccessPolicy'
            'DefaultAppManagementPolicy'
            'Settings'
            'SecureScore'
            'PIMSettings'
            'Domains'
            'B2BManagementPolicy'
            'DeviceRegistrationPolicy'
            'OAuth2PermissionGrants'
            'AppRoleAssignments'
            'LicenseOverview'
            'MFAState'
            'BitlockerKeys'
        )

        foreach ($CacheFunction in $BasicCacheFunctions) {
            $Tasks.Add(@{
                    FunctionName = 'ExecCIPPDBCache'
                    Name         = $CacheFunction
                    TenantFilter = $TenantFilter
                    QueueId      = $QueueId
                })
        }
        #endregion All Licenses

        #region Exchange Licensed - Exchange Online features
        if ($ExchangeCapable) {
            $ExchangeCacheFunctions = @(
                'ExoAntiPhishPolicies'
                'ExoMalwareFilterPolicies'
                'ExoSafeLinksPolicies'
                'ExoSafeAttachmentPolicies'
                'ExoTransportRules'
                'ExoDkimSigningConfig'
                'ExoOrganizationConfig'
                'ExoAcceptedDomains'
                'ExoHostedContentFilterPolicy'
                'ExoHostedOutboundSpamFilterPolicy'
                'ExoAntiPhishPolicy'
                'ExoSafeLinksPolicy'
                'ExoSafeAttachmentPolicy'
                'ExoMalwareFilterPolicy'
                'ExoAtpPolicyForO365'
                'ExoQuarantinePolicy'
                'ExoRemoteDomain'
                'ExoSharingPolicy'
                'ExoAdminAuditLogConfig'
                'ExoPresetSecurityPolicy'
                'ExoTenantAllowBlockList'
                'Mailboxes'
                'CASMailboxes'
                'MailboxUsage'
                'OneDriveUsage'
            )

            foreach ($CacheFunction in $ExchangeCacheFunctions) {
                $Tasks.Add(@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $CacheFunction
                        TenantFilter = $TenantFilter
                        QueueId      = $QueueId
                    })
            }
        } else {
            Write-Host "Skipping Exchange Online data collection for $TenantFilter - no required license"
        }
        #endregion Exchange Licensed

        #region Conditional Access Licensed - Azure AD Premium features
        if ($ConditionalAccessCapable) {
            $ConditionalAccessCacheFunctions = @(
                'ConditionalAccessPolicies'
                #'AuthenticationFlowsPolicy'
                'CredentialUserRegistrationDetails'
                'UserRegistrationDetails'
            )
            foreach ($CacheFunction in $ConditionalAccessCacheFunctions) {
                $Tasks.Add(@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $CacheFunction
                        TenantFilter = $TenantFilter
                        QueueId      = $QueueId
                    })
            }
        } else {
            Write-Host "Skipping Conditional Access data collection for $TenantFilter - no required license"
        }
        #endregion Conditional Access Licensed

        #region Azure AD Premium P2 - Identity Protection/PIM features
        if ($AzureADPremiumP2Capable) {
            $P2CacheFunctions = @(
                'RiskyUsers'
                'RiskyServicePrincipals'
                'ServicePrincipalRiskDetections'
                'RiskDetections'
                'RoleEligibilitySchedules'
                'RoleAssignmentSchedules'
                'RoleManagementPolicies'
            )
            foreach ($CacheFunction in $P2CacheFunctions) {
                $Tasks.Add(@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $CacheFunction
                        TenantFilter = $TenantFilter
                        QueueId      = $QueueId
                    })
            }
        } else {
            Write-Host "Skipping Azure AD Premium P2 data collection for $TenantFilter - no required license"
        }
        #endregion Azure AD Premium P2

        #region Intune Licensed - Intune management features
        if ($IntuneCapable) {
            $IntuneCacheFunctions = @(
                'ManagedDevices'
                'IntunePolicies'
                'ManagedDeviceEncryptionStates'
                'IntuneAppProtectionPolicies'
                'DetectedApps'
            )
            foreach ($CacheFunction in $IntuneCacheFunctions) {
                $Tasks.Add(@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $CacheFunction
                        TenantFilter = $TenantFilter
                        QueueId      = $QueueId
                    })
            }
        } else {
            Write-Host "Skipping Intune data collection for $TenantFilter - no required license"
        }
        #endregion Intune Licensed

        Write-Information "Built $($Tasks.Count) cache tasks for tenant $TenantFilter"

        # Return the task list — the PostExecution function will aggregate and start a flat orchestrator
        return @($Tasks)

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to build cache task list: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @()
    }
}
