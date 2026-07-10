function Invoke-ListSiteProperties {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Returns a single site's admin-level properties (sharing, lifecycle and version policy)
        via the SharePoint admin CSOM API, with enum values translated to friendly names so
        the Edit Site form can consume and round-trip them.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl

    # SPO enum value -> friendly name maps (reverse of the maps in Invoke-ExecSetSiteProperties)
    $SharingCapabilityNames = @{ 0 = 'Disabled'; 1 = 'ExternalUserSharingOnly'; 2 = 'ExternalUserAndGuestSharing'; 3 = 'ExistingExternalUserSharingOnly' }
    $LinkTypeNames = @{ 0 = 'None'; 1 = 'Direct'; 2 = 'Internal'; 3 = 'AnonymousAccess' }
    $LinkPermissionNames = @{ 0 = 'None'; 1 = 'View'; 2 = 'Edit' }
    $DomainRestrictionNames = @{ 0 = 'None'; 1 = 'AllowList'; 2 = 'BlockList' }

    try {
        if (-not $SiteUrl) { throw 'SiteUrl is required.' }
        $Site = Get-CIPPSPOSite -TenantFilter $TenantFilter -SiteUrl $SiteUrl

        $Body = [PSCustomObject]@{
            Url                                         = $Site.Url
            Title                                       = $Site.Title
            Template                                    = $Site.Template
            # Sharing
            SharingCapability                           = $SharingCapabilityNames[[int]$Site.SharingCapability] ?? $Site.SharingCapability
            DefaultSharingLinkType                      = $LinkTypeNames[[int]$Site.DefaultSharingLinkType] ?? $Site.DefaultSharingLinkType
            DefaultLinkPermission                       = $LinkPermissionNames[[int]$Site.DefaultLinkPermission] ?? $Site.DefaultLinkPermission
            SharingDomainRestrictionMode                = $DomainRestrictionNames[[int]$Site.SharingDomainRestrictionMode] ?? $Site.SharingDomainRestrictionMode
            SharingAllowedDomainList                    = $Site.SharingAllowedDomainList
            SharingBlockedDomainList                    = $Site.SharingBlockedDomainList
            OverrideTenantAnonymousLinkExpirationPolicy = [bool]$Site.OverrideTenantAnonymousLinkExpirationPolicy
            AnonymousLinkExpirationInDays               = $Site.AnonymousLinkExpirationInDays
            # Lifecycle
            LockState                                   = $Site.LockState
            StorageMaximumLevel                         = $Site.StorageMaximumLevel
            StorageWarningLevel                         = $Site.StorageWarningLevel
            StorageUsage                                = $Site.StorageUsage
            # Version policy
            InheritVersionPolicyFromTenant              = [bool]$Site.InheritVersionPolicyFromTenant
            EnableAutoExpirationVersionTrim             = [bool]$Site.EnableAutoExpirationVersionTrim
            MajorVersionLimit                           = $Site.MajorVersionLimit
            ExpireVersionsAfterDays                     = $Site.ExpireVersionsAfterDays
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to get site properties for $($SiteUrl): $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body }
        })
}
