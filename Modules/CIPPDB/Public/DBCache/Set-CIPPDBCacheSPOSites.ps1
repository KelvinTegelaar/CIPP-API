function Set-CIPPDBCacheSPOSites {
    <#
    .SYNOPSIS
        Caches per-site SharePoint Online admin settings for every site collection

    .DESCRIPTION
        Generic per-site SharePoint cache (Type 'SPOSites'): one row per site collection with the
        admin-manageable settings (sharing, lifecycle, version policy, People Picker, unmanaged-device
        access), keyed by site id. Any site-level standard can read it. Populated from Get-CIPPSPOSite;
        SharePoint app-only requires the certificate (delegated is not available on every tenant), so
        the read always uses -UseCertificate.

    .PARAMETER TenantFilter
        The tenant to cache SharePoint site settings for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint site settings' -sev Debug

        $Sites = @(Get-CIPPSPOSite -TenantFilter $TenantFilter -UseCertificate | Where-Object { $_ -and $_.Url })

        # Admin-manageable per-site settings (mirrors Invoke-ListSiteProperties' field set, plus the
        # People Picker and unmanaged-device policy). Enum values stay numeric as CSOM returns them.
        $Rows = @($Sites | Select-Object `
                @{ n = 'id'; e = { "$($_.SiteId)" } }, Url, Title, Template,
            @{ n = 'GroupId'; e = { "$($_.GroupId)" } },
            SharingCapability, DefaultSharingLinkType, DefaultLinkPermission, SharingDomainRestrictionMode,
            SharingAllowedDomainList, SharingBlockedDomainList, OverrideTenantAnonymousLinkExpirationPolicy,
            AnonymousLinkExpirationInDays, LockState, StorageMaximumLevel, StorageWarningLevel, StorageUsage,
            InheritVersionPolicyFromTenant, EnableAutoExpirationVersionTrim, MajorVersionLimit,
            ExpireVersionsAfterDays, ConditionalAccessPolicy, ShowPeoplePickerSuggestionsForGuestUsers)

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOSites' -Data $Rows -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) SharePoint site settings" -sev Debug

    } catch {
        # A tenant with no SharePoint app-only consent answers 401 every run until that changes;
        # record it and move on rather than failing the whole collection for it.
        if ($_.Exception.Data['SPOAccessDenied'] -or $_.Exception.Message -match '\b401\b|unauthorized') {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Skipped SharePoint site cache: $($_.Exception.Message)" -sev Warning
            return
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint site settings: $($_.Exception.Message)" -sev Error
        throw
    }
}
