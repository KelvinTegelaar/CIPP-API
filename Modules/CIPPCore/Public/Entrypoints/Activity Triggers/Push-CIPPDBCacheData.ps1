function Push-CIPPDBCacheData {
    <#
    .SYNOPSIS
        Activity function to collect and cache all data for a single tenant

    .DESCRIPTION
        Calls all collection functions sequentially, storing data immediately after each collection

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)
    Write-Host "Starting cache collection for tenant: $($Item.TenantFilter) - Queue: $($Item.QueueName) (ID: $($Item.QueueId))"
    $TenantFilter = $Item.TenantFilter
    $Type = $Item.Type ?? 'Default'

    #This collects all data for a tenant and caches it in the CIPP Reporting database. DO NOT ADD PROCESSING OR LOGIC HERE.
    #The point of this file is to always be <10 minutes execution time.
    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting database cache collection for tenant' -sev Info

        # Check tenant capabilities for license-specific features
        $IntuneCapable = Test-CIPPStandardLicense -StandardName 'IntuneLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog
        $ConditionalAccessCapable = Test-CIPPStandardLicense -StandardName 'ConditionalAccessLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2') -SkipLog
        $AzureADPremiumP2Capable = Test-CIPPStandardLicense -StandardName 'AzureADPremiumP2LicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog
        $ExchangeCapable = Test-CIPPStandardLicense -StandardName 'ExchangeLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') -SkipLog

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "License capabilities - Intune: $IntuneCapable, Conditional Access: $ConditionalAccessCapable, Azure AD Premium P2: $AzureADPremiumP2Capable, Exchange: $ExchangeCapable" -sev Info

        switch ($Type) {
            'Default' {
                #region All Licenses - Basic tenant data collection
                Write-Host 'Getting cache for Users'
                try { Set-CIPPDBCacheUsers -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Users collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Groups'
                try { Set-CIPPDBCacheGroups -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Groups collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Guests'
                try { Set-CIPPDBCacheGuests -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Guests collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for ServicePrincipals'
                try { Set-CIPPDBCacheServicePrincipals -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ServicePrincipals collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Apps'
                try { Set-CIPPDBCacheApps -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Apps collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Devices'
                try { Set-CIPPDBCacheDevices -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Devices collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Organization'
                try { Set-CIPPDBCacheOrganization -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Organization collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Roles'
                try { Set-CIPPDBCacheRoles -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Roles collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for AdminConsentRequestPolicy'
                try { Set-CIPPDBCacheAdminConsentRequestPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AdminConsentRequestPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for AuthorizationPolicy'
                try { Set-CIPPDBCacheAuthorizationPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AuthorizationPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for AuthenticationMethodsPolicy'
                try { Set-CIPPDBCacheAuthenticationMethodsPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AuthenticationMethodsPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for DeviceSettings'
                try { Set-CIPPDBCacheDeviceSettings -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DeviceSettings collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for DirectoryRecommendations'
                try { Set-CIPPDBCacheDirectoryRecommendations -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DirectoryRecommendations collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for CrossTenantAccessPolicy'
                try { Set-CIPPDBCacheCrossTenantAccessPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "CrossTenantAccessPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for DefaultAppManagementPolicy'
                try { Set-CIPPDBCacheDefaultAppManagementPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DefaultAppManagementPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Settings'
                try { Set-CIPPDBCacheSettings -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Settings collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for SecureScore'
                try { Set-CIPPDBCacheSecureScore -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SecureScore collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for PIMSettings'
                try { Set-CIPPDBCachePIMSettings -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "PIMSettings collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for Domains'
                try { Set-CIPPDBCacheDomains -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Domains collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for RoleEligibilitySchedules'
                try { Set-CIPPDBCacheRoleEligibilitySchedules -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RoleEligibilitySchedules collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for RoleManagementPolicies'
                try { Set-CIPPDBCacheRoleManagementPolicies -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RoleManagementPolicies collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for RoleAssignmentScheduleInstances'
                try { Set-CIPPDBCacheRoleAssignmentScheduleInstances -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RoleAssignmentScheduleInstances collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for B2BManagementPolicy'
                try { Set-CIPPDBCacheB2BManagementPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "B2BManagementPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for AuthenticationFlowsPolicy'
                try { Set-CIPPDBCacheAuthenticationFlowsPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AuthenticationFlowsPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for DeviceRegistrationPolicy'
                try { Set-CIPPDBCacheDeviceRegistrationPolicy -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DeviceRegistrationPolicy collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for CredentialUserRegistrationDetails'
                try { Set-CIPPDBCacheCredentialUserRegistrationDetails -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "CredentialUserRegistrationDetails collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for UserRegistrationDetails'
                try { Set-CIPPDBCacheUserRegistrationDetails -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "UserRegistrationDetails collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for OAuth2PermissionGrants'
                try { Set-CIPPDBCacheOAuth2PermissionGrants -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OAuth2PermissionGrants collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for AppRoleAssignments'
                try { Set-CIPPDBCacheAppRoleAssignments -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AppRoleAssignments collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for License Overview'
                try { Set-CIPPDBCacheLicenseOverview -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "License Overview collection failed: $($_.Exception.Message)" -sev Error
                }

                Write-Host 'Getting cache for MFA State'
                try { Set-CIPPDBCacheMFAState -TenantFilter $TenantFilter } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "MFA State collection failed: $($_.Exception.Message)" -sev Error
                }
                #endregion All Licenses

                #region Exchange Licensed - Exchange Online features
                if ($ExchangeCapable) {
                    Write-Host 'Getting cache for ExoAntiPhishPolicies'
                    try { Set-CIPPDBCacheExoAntiPhishPolicies -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoAntiPhishPolicies collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoMalwareFilterPolicies'
                    try { Set-CIPPDBCacheExoMalwareFilterPolicies -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoMalwareFilterPolicies collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoSafeLinksPolicies'
                    try { Set-CIPPDBCacheExoSafeLinksPolicies -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoSafeLinksPolicies collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoSafeAttachmentPolicies'
                    try { Set-CIPPDBCacheExoSafeAttachmentPolicies -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoSafeAttachmentPolicies collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoTransportRules'
                    try { Set-CIPPDBCacheExoTransportRules -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoTransportRules collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoDkimSigningConfig'
                    try { Set-CIPPDBCacheExoDkimSigningConfig -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoDkimSigningConfig collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoOrganizationConfig'
                    try { Set-CIPPDBCacheExoOrganizationConfig -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoOrganizationConfig collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoAcceptedDomains'
                    try { Set-CIPPDBCacheExoAcceptedDomains -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoAcceptedDomains collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoHostedContentFilterPolicy'
                    try { Set-CIPPDBCacheExoHostedContentFilterPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoHostedContentFilterPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoHostedOutboundSpamFilterPolicy'
                    try { Set-CIPPDBCacheExoHostedOutboundSpamFilterPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoHostedOutboundSpamFilterPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoAntiPhishPolicy'
                    try { Set-CIPPDBCacheExoAntiPhishPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoAntiPhishPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoSafeLinksPolicy'
                    try { Set-CIPPDBCacheExoSafeLinksPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoSafeLinksPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoSafeAttachmentPolicy'
                    try { Set-CIPPDBCacheExoSafeAttachmentPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoSafeAttachmentPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoMalwareFilterPolicy'
                    try { Set-CIPPDBCacheExoMalwareFilterPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoMalwareFilterPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoAtpPolicyForO365'
                    try { Set-CIPPDBCacheExoAtpPolicyForO365 -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoAtpPolicyForO365 collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoQuarantinePolicy'
                    try { Set-CIPPDBCacheExoQuarantinePolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoQuarantinePolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoRemoteDomain'
                    try { Set-CIPPDBCacheExoRemoteDomain -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoRemoteDomain collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoSharingPolicy'
                    try { Set-CIPPDBCacheExoSharingPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoSharingPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoAdminAuditLogConfig'
                    try { Set-CIPPDBCacheExoAdminAuditLogConfig -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoAdminAuditLogConfig collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoPresetSecurityPolicy'
                    try { Set-CIPPDBCacheExoPresetSecurityPolicy -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoPresetSecurityPolicy collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ExoTenantAllowBlockList'
                    try { Set-CIPPDBCacheExoTenantAllowBlockList -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoTenantAllowBlockList collection failed: $($_.Exception.Message)" -sev Error
                    }
                } else {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipping Exchange Online data collection - tenant does not have required license' -sev Info
                }
                #endregion Exchange Licensed

                #region Conditional Access Licensed - Azure AD Premium features
                if ($ConditionalAccessCapable) {
                    Write-Host 'Getting cache for ConditionalAccessPolicies'
                    try { Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ConditionalAccessPolicies collection failed: $($_.Exception.Message)" -sev Error
                    }
                } else {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipping Conditional Access data collection - tenant does not have required license' -sev Info
                }
                #endregion Conditional Access Licensed

                #region Azure AD Premium P2 - Identity Protection features
                if ($AzureADPremiumP2Capable) {
                    Write-Host 'Getting cache for RiskyUsers'
                    try { Set-CIPPDBCacheRiskyUsers -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RiskyUsers collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for RiskyServicePrincipals'
                    try { Set-CIPPDBCacheRiskyServicePrincipals -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RiskyServicePrincipals collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ServicePrincipalRiskDetections'
                    try { Set-CIPPDBCacheServicePrincipalRiskDetections -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ServicePrincipalRiskDetections collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for RiskDetections'
                    try { Set-CIPPDBCacheRiskDetections -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RiskDetections collection failed: $($_.Exception.Message)" -sev Error
                    }
                } else {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipping Azure AD Premium P2 Identity Protection data collection - tenant does not have required license' -sev Info
                }
                #endregion Azure AD Premium P2

                #region Intune Licensed - Intune management features
                if ($IntuneCapable) {
                    Write-Host 'Getting cache for ManagedDevices'
                    try { Set-CIPPDBCacheManagedDevices -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ManagedDevices collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for IntunePolicies'
                    try { Set-CIPPDBCacheIntunePolicies -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "IntunePolicies collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for ManagedDeviceEncryptionStates'
                    try { Set-CIPPDBCacheManagedDeviceEncryptionStates -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ManagedDeviceEncryptionStates collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for IntuneAppProtectionPolicies'
                    try { Set-CIPPDBCacheIntuneAppProtectionPolicies -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "IntuneAppProtectionPolicies collection failed: $($_.Exception.Message)" -sev Error
                    }
                } else {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipping Intune data collection - tenant does not have required license' -sev Info
                }
                #endregion Intune Licensed
            }
            'Mailboxes' {
                if ($ExchangeCapable) {
                    Write-Host 'Getting cache for Mailboxes'
                    try { Set-CIPPDBCacheMailboxes -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Mailboxes collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for MailboxUsage'
                    try { Set-CIPPDBCacheMailboxUsage -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "MailboxUsage collection failed: $($_.Exception.Message)" -sev Error
                    }

                    Write-Host 'Getting cache for OneDriveUsage'
                    try { Set-CIPPDBCacheOneDriveUsage -TenantFilter $TenantFilter } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDriveUsage collection failed: $($_.Exception.Message)" -sev Error
                    }
                } else {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipping Mailboxes data collection - tenant does not have required Exchange license' -sev Info
                }
            }
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Completed database cache collection for tenant' -sev Info

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to complete database cache collection: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
