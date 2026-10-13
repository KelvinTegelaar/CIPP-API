function Set-CIPPDBCacheSPOSites {
    <#
    .SYNOPSIS
        Caches per-site SharePoint Online admin settings for every site collection

    .DESCRIPTION
        Generic per-site SharePoint cache (Type 'SPOSites'): one row per site collection with the
        admin-manageable settings (site owner, sharing controls, lifecycle, version policy, People
        Picker, unmanaged-device access), keyed by site id. Any site-level standard or report can read
        it. The tenant-wide enumeration (Get-CIPPSPOSite) supplies the site list and the fields it is
        accurate for; the ~19 fields it only returns as defaults (owner, per-site sharing, People
        Picker, ...) are filled from an authoritative per-site read (Get-CIPPSPOSiteBulk, batched and
        concurrency-capped). SharePoint app-only requires the certificate (delegated is not available on
        every tenant), so both reads use -UseCertificate.

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

        # The tenant-wide enumeration is fast but returns DEFAULT/empty values for ~19 per-site fields
        # (site owner, per-site sharing controls, ShowPeoplePickerSuggestionsForGuestUsers, ...) - only
        # the per-site GetSitePropertiesByUrl returns them (confirmed on a live tenant, and confirmed no
        # Graph/enumeration variant supplies them). So the enumeration gives us the URL list + the fields
        # it IS accurate for, and one authoritative per-site read - batched and concurrency-capped to stay
        # under SharePoint's CSOM throttle - fills in the rest. A per-site read failure falls back to the
        # enumeration value for that site.

        # Fields the enumeration only returns as defaults - take the authoritative per-site value, and
        # fall back to the (less accurate) enumeration value when the per-site read did not return.
        $AuthoritativeFields = @(
            'ShowPeoplePickerSuggestionsForGuestUsers', 'OwnerName', 'OwnerEmail', 'OwnerLoginName',
            'GroupOwnerLoginName', 'IsGroupOwnerSiteAdmin', 'AllowEditing', 'AllowFileArchive',
            'DefaultShareLinkScope', 'DefaultMainLinkScope', 'DisableCompanyWideSharingLinks',
            'LoopDefaultSharingLinkScope', 'LoopDefaultSharingLinkRole', 'BlockDownloadLinksFileType',
            'LimitedAccessFileType', 'RequestFilesLinkEnabled', 'RequestFilesLinkExpirationInDays',
            'SharingLockDownEnabled', 'SharingLockDownCanBeCleared', 'ReadOnlyForUnmanagedDevices',
            'RestrictedAccessControl', 'DisableAppViews', 'DisableFlows', 'SandboxedCodeActivationCapability',
            'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'WebsCount', 'Status'
        )

        # Accurate from the enumeration. Enum values stay numeric as CSOM returns them.
        $EnumerationFields = @(
            'Url', 'Title', 'Template', 'GroupId', 'SharingCapability', 'DefaultSharingLinkType',
            'DefaultLinkPermission', 'SharingDomainRestrictionMode', 'SharingAllowedDomainList',
            'SharingBlockedDomainList', 'OverrideTenantAnonymousLinkExpirationPolicy',
            'AnonymousLinkExpirationInDays', 'LockState', 'StorageMaximumLevel', 'StorageWarningLevel',
            'StorageUsage', 'InheritVersionPolicyFromTenant', 'EnableAutoExpirationVersionTrim',
            'MajorVersionLimit', 'ExpireVersionsAfterDays', 'ConditionalAccessPolicy'
        )

        # Read, merged and written a chunk at a time so a tenant with tens of thousands of sites never
        # holds them all at once.
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOSites' -AddCount -ClearOnEmpty }.GetSteppablePipeline()
        $Writer.Begin($true)
        $Chunk = [System.Collections.Generic.List[object]]::new()
        $Cached = 0
        $Missing = 0
        $BulkError = $null
        $WriteChunk = {
            $AuthByUrl = @{}
            try {
                foreach ($Result in @(Get-CIPPSPOSiteBulk -TenantFilter $TenantFilter -SiteUrls @($Chunk.Url) -MaxConcurrency 4 -BatchSize 8 -Properties $AuthoritativeFields -UseCertificate)) {
                    if ($Result.Success -and $Result.Site) { $AuthByUrl["$($Result.SiteUrl)"] = $Result.Site }
                }
            } catch {
                $BulkError = $_.Exception.Message
            }
            foreach ($Site in $Chunk) {
                $Auth = $AuthByUrl["$($Site.Url)"]
                if (-not $Auth) { $Missing++ }
                $Source = if ($Auth) { $Auth } else { $Site }
                $Row = [ordered]@{ id = "$($Site.SiteId)" }
                foreach ($Field in $EnumerationFields) { $Row[$Field] = $Site.$Field }
                $Row['GroupId'] = "$($Site.GroupId)"
                foreach ($Field in $AuthoritativeFields) { $Row[$Field] = $Source.$Field }
                $Writer.Process([PSCustomObject]$Row)
                $Cached++
            }
            $Chunk.Clear()
        }

        Get-CIPPSPOSite -TenantFilter $TenantFilter -UseCertificate -Properties (@('SiteId') + $EnumerationFields + $AuthoritativeFields) | ForEach-Object {
            if ($_ -and $_.Url) {
                $Chunk.Add($_)
                if ($Chunk.Count -ge 500) { . $WriteChunk }
            }
        }
        if ($Chunk.Count -gt 0) { . $WriteChunk }
        $Writer.End()

        if ($BulkError) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SPOSites: authoritative per-site read failed; $Missing of $Cached sites fell back to the enumeration values for this run: $BulkError" -sev Warning
        } elseif ($Missing -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SPOSites: $Missing of $Cached sites fell back to enumeration values (authoritative per-site read did not return them)" -sev Debug
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $Cached SharePoint site settings" -sev Debug

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
