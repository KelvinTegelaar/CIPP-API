function Set-CIPPDBCacheIntuneMobileApps {
    <#
    .SYNOPSIS
        Caches Intune mobile apps (summary fields) for a tenant.

    .DESCRIPTION
        Thin single-family collector for the IntuneMobileApps cache type, which the
        Set-CIPPDBCacheIntunePolicies umbrella also writes on its schedule. It exists so the
        convention lookup (Set-CIPPDBCache<Type>) resolves for collect-on-miss and for the
        post-remediation refresh. Same $select as the umbrella's family entry; the umbrella's
        per-app assignment fan-out is not repeated here, so rows from this collector simply
        lack the assignments property.

    .PARAMETER TenantFilter
        The tenant to cache mobile apps for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneMobileAppsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping mobile apps cache' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneMobileApps' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune mobile apps' -sev Debug
        $Apps = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$top=999&$select=id,displayName,description,publisher,isAssigned,createdDateTime,lastModifiedDateTime' -tenantid $TenantFilter
        if (-not $Apps) { $Apps = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneMobileApps' -Data @($Apps) -AddCount -ClearOnEmpty

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Apps | Measure-Object).Count) mobile apps" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mobile apps: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
