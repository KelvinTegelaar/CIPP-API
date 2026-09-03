function Set-CIPPDBCacheSPOSites {
    <#
    .SYNOPSIS
        Caches SharePoint People Picker guest visibility for the tenant default and every site

    .DESCRIPTION
        One self-contained cache (Type 'SPOSites') covering both levels the setting is applied at:
        a single 'tenant' row from Get-CIPPSPOTenant and one 'site' row per site collection from
        Get-CIPPSPOSite. The standards read only this cache, so both are collected here with the
        certificate (SharePoint app-only requires it; delegated is not available on every tenant).

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint People Picker settings' -sev Debug

        $Tenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter -SkipCache -UseCertificate
        $Sites = @(Get-CIPPSPOSite -TenantFilter $TenantFilter -UseCertificate)

        $Rows = @(
            if ($Tenant) {
                [PSCustomObject]@{ id = 'tenant-default'; Scope = 'tenant'; Url = $null; ShowPeoplePickerSuggestionsForGuestUsers = [bool]$Tenant.ShowPeoplePickerSuggestionsForGuestUsers }
            }
            foreach ($Site in $Sites) {
                if (-not $Site) { continue }
                [PSCustomObject]@{ id = "$($Site.SiteId)"; Scope = 'site'; Url = $Site.Url; ShowPeoplePickerSuggestionsForGuestUsers = [bool]$Site.ShowPeoplePickerSuggestionsForGuestUsers }
            }
        )

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOSites' -Data $Rows -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) SharePoint People Picker rows" -sev Debug

    } catch {
        # A tenant with no SharePoint app-only consent answers 401 every run until that changes;
        # record it and move on rather than failing the whole collection for it.
        if ($_.Exception.Data['SPOAccessDenied'] -or $_.Exception.Message -match '\b401\b|unauthorized') {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Skipped SharePoint People Picker cache: $($_.Exception.Message)" -sev Warning
            return
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint People Picker settings: $($_.Exception.Message)" -sev Error
        throw
    }
}
