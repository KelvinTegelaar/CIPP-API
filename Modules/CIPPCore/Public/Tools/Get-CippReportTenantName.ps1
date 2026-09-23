function Get-CippReportTenantName {
    <#
    .SYNOPSIS
        How a report names its tenant, as the branding decides.
    .DESCRIPTION
        Every server-rendered report puts the tenant's name on its cover, in its prose and, through
        %tenantname%, in its footer. The branding's tenantLabel says which name that is:

          alias   - the name CIPP shows for the tenant: its alias when one is set, else its name (default)
          name    - the Microsoft 365 organisation name, alias or not
          domain  - the tenant's default domain

        A preset's choice wins over the global setting when a preset id is given, exactly as the
        rest of the branding resolves. Anything that cannot be read falls back to the next best
        thing, and finally to the tenant filter itself, so a report always has something to say.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [string]$BrandingPresetId,
        # Already-resolved branding, when the caller has it; otherwise the preset or global settings are read.
        $Branding
    )

    $Tenant = try { Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1 } catch { $null }
    $Shown = if ($Tenant.displayName) { [string]$Tenant.displayName } else { $TenantFilter }

    if ($null -eq $Branding) {
        $Branding = try {
            $Preset = if ($BrandingPresetId) { Get-CIPPBrandingPreset -Id $BrandingPresetId -SkipImageData | Select-Object -First 1 }
            if ($Preset) { $Preset } else { Get-CIPPBrandingSettings }
        } catch { $null }
    }

    switch ([string]$Branding.tenantLabel) {
        'domain' {
            if ($Tenant.defaultDomainName) { [string]$Tenant.defaultDomainName } else { $TenantFilter }
        }
        'name' {
            # The organisation's own name, which the tenant cache overwrites with an alias when one is set.
            $Organisation = try {
                New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName' -tenantid $TenantFilter -AsApp $true | Select-Object -First 1
            } catch { $null }
            if ($Organisation.displayName) { [string]$Organisation.displayName } else { $Shown }
        }
        default { $Shown }
    }
}
