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

    $TenantFilter = $Item.TenantFilter
    #This collects all data for a tenant and caches it in the CIPP Reporting database. DO NOT ADD PROCESSING OR LOGIC HERE.
    #The point of this file is to always be <10 minutes execution time.
    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting database cache collection for tenant' -sev Info

        try { Set-CIPPDBCacheUsers -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Users collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheGroups -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Groups collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheGuests -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Guests collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheServicePrincipals -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ServicePrincipals collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheApps -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Apps collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheDevices -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Devices collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheManagedDevices -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ManagedDevices collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheOrganization -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Organization collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheRoles -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Roles collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheAdminConsentRequestPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AdminConsentRequestPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheAuthorizationPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AuthorizationPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheAuthenticationMethodsPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AuthenticationMethodsPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheDeviceSettings -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DeviceSettings collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheDirectoryRecommendations -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DirectoryRecommendations collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheCrossTenantAccessPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "CrossTenantAccessPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheDefaultAppManagementPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DefaultAppManagementPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheSettings -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Settings collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheSecureScore -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SecureScore collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheIntunePolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "IntunePolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ConditionalAccessPolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCachePIMSettings -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "PIMSettings collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheDomains -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Domains collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheRoleEligibilitySchedules -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RoleEligibilitySchedules collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheRoleManagementPolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RoleManagementPolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheRoleAssignmentScheduleInstances -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RoleAssignmentScheduleInstances collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheB2BManagementPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "B2BManagementPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheAuthenticationFlowsPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AuthenticationFlowsPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheRiskyUsers -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RiskyUsers collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheRiskyServicePrincipals -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RiskyServicePrincipals collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheServicePrincipalRiskDetections -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ServicePrincipalRiskDetections collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheRiskDetections -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "RiskDetections collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheDeviceRegistrationPolicy -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "DeviceRegistrationPolicy collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheCredentialUserRegistrationDetails -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "CredentialUserRegistrationDetails collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheUserRegistrationDetails -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "UserRegistrationDetails collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheManagedDeviceEncryptionStates -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ManagedDeviceEncryptionStates collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheOAuth2PermissionGrants -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OAuth2PermissionGrants collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheAppRoleAssignments -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "AppRoleAssignments collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoAntiPhishPolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoAntiPhishPolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoMalwareFilterPolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoMalwareFilterPolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoSafeLinksPolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoSafeLinksPolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoSafeAttachmentPolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoSafeAttachmentPolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoTransportRules -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoTransportRules collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoDkimSigningConfig -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoDkimSigningConfig collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoOrganizationConfig -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoOrganizationConfig collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheExoAcceptedDomains -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "ExoAcceptedDomains collection failed: $($_.Exception.Message)" -sev Error
        }

        try { Set-CIPPDBCacheIntuneAppProtectionPolicies -TenantFilter $TenantFilter } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "IntuneAppProtectionPolicies collection failed: $($_.Exception.Message)" -sev Error
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Completed database cache collection for tenant' -sev Info

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to complete database cache collection: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
