function Set-CIPPDBCacheIntuneWindowsAutopilotDeploymentProfiles {
    <#
    .SYNOPSIS
        Caches Windows Autopilot deployment profiles (with assignments) for a tenant.

    .DESCRIPTION
        Thin single-family collector for the IntuneWindowsAutopilotDeploymentProfiles cache
        type, which the Set-CIPPDBCacheIntunePolicies umbrella also writes on its schedule. It
        exists so the convention lookup (Set-CIPPDBCache<Type>) resolves for collect-on-miss
        and for the post-remediation refresh. Same URI as the umbrella's family entry.

    .PARAMETER TenantFilter
        The tenant to cache Autopilot deployment profiles for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneAutopilotProfilesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping Autopilot profiles cache' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneWindowsAutopilotDeploymentProfiles' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Autopilot deployment profiles' -sev Debug
        $Profiles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?$top=999&$expand=assignments' -tenantid $TenantFilter
        if (-not $Profiles) { $Profiles = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneWindowsAutopilotDeploymentProfiles' -Data @($Profiles) -AddCount -ClearOnEmpty

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Profiles | Measure-Object).Count) Autopilot deployment profiles" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Autopilot deployment profiles: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
