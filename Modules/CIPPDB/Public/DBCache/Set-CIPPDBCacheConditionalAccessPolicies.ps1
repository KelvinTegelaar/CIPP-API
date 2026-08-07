function Set-CIPPDBCacheConditionalAccessPolicies {
    <#
    .SYNOPSIS
        Caches all Conditional Access policies, named locations, and authentication strengths for a tenant (if CA capable)

    .PARAMETER TenantFilter
        The tenant to cache CA policies for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessCache' -TenantFilter $TenantFilter -Preset Entra -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Azure AD Premium license, skipping CA' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Conditional Access policies' -sev Debug

        try {
            $CAPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
            # -ClearOnEmpty marks the response AUTHORITATIVE: the read throws on failure,
            # so reaching here means this is the tenant's full policy set. Cleanup then
            # keys off the exact row keys written instead of the timestamp heuristic,
            # whose 5-minute skew margin left policies deleted just before a re-collect
            # sitting in the cache. An authoritative EMPTY set clears the cache too - a
            # tenant whose last policy was removed must not keep reporting yesterday's.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' -Data @($CAPolicies) -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($CAPolicies).Count) CA policies" -sev Debug
            $CAPolicies = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache CA policies: $($_.Exception.Message)" -sev Warning
        }

        try {
            $NamedLocations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NamedLocations' -Data @($NamedLocations) -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($NamedLocations).Count) named locations" -sev Debug
            $NamedLocations = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache named locations: $($_.Exception.Message)" -sev Warning
        }

        try {
            $AuthStrengths = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies' -tenantid $TenantFilter
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthenticationStrengths' -Data @($AuthStrengths) -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($AuthStrengths).Count) authentication strengths" -sev Debug
            $AuthStrengths = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache authentication strengths: $($_.Exception.Message)" -sev Warning
        }

        try {
            $SecurityDefaults = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter -AsApp $true
            if ($SecurityDefaults) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecurityDefaults' -Data @($SecurityDefaults)
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached Security Defaults policy (isEnabled=$($SecurityDefaults.isEnabled))" -sev Debug
            }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Security Defaults: $($_.Exception.Message)" -sev Warning
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CA data successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Conditional Access data: $($_.Exception.Message)" -sev Error
    }
}
