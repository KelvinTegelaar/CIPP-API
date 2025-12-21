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

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Completed database cache collection for tenant' -sev Info

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to complete database cache collection: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
