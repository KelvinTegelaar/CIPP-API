function Set-CIPPDBCacheIntuneDataProcessorOnboarding {
    <#
    .SYNOPSIS
        Caches the Windows data processor service onboarding state for a tenant

    .DESCRIPTION
        Caches deviceManagement/dataProcessorServiceForWindowsFeaturesOnboarding
        (areDataProcessorServiceForWindowsFeaturesEnabled, hasValidWindowsLicense)
        used by the IntuneWindowsDiagnostic standard.

    .PARAMETER TenantFilter
        The tenant to cache the data processor onboarding state for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneDataProcessorOnboardingCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping data processor onboarding cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Windows data processor service onboarding state' -sev Debug

        $Onboarding = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/dataProcessorServiceForWindowsFeaturesOnboarding' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDataProcessorOnboarding' -Data @($Onboarding) -AddCount
        $Onboarding = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Windows data processor service onboarding state successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Windows data processor service onboarding state: $($_.Exception.Message)" -sev Error
    }
}
