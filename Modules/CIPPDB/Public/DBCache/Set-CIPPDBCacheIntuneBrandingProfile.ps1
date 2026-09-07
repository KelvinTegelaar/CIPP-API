function Set-CIPPDBCacheIntuneBrandingProfile {
    <#
    .SYNOPSIS
        Caches Intune Company Portal branding profiles for a tenant

    .PARAMETER TenantFilter
        The tenant to cache Intune branding profiles for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneBrandingProfileCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping Intune branding profile cache' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneBrandingProfile' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune branding profiles' -sev Debug

        # -AsApp matches the old intuneBrandingProfile standard, which reads this endpoint app-only.
        $BrandingProfiles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/intuneBrandingProfiles' -tenantid $TenantFilter -AsApp $true
        if (-not $BrandingProfiles) { $BrandingProfiles = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneBrandingProfile' -Data @($BrandingProfiles) -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($BrandingProfiles | Measure-Object).Count) Intune branding profiles" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune branding profiles: $($_.Exception.Message)" -sev Error
    }
}
