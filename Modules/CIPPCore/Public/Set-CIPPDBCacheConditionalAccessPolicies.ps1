function Set-CIPPDBCacheConditionalAccessPolicies {
    <#
    .SYNOPSIS
        Caches all Conditional Access policies, named locations, and authentication strengths for a tenant (if CA capable)

    .PARAMETER TenantFilter
        The tenant to cache CA policies for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessCache' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2') -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Azure AD Premium license, skipping CA' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Conditional Access policies' -sev Debug

        try {
            $CAPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
            if ($CAPolicies) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' -Data $CAPolicies
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' -Data $CAPolicies -Count
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($CAPolicies.Count) CA policies" -sev Debug
            }
            $CAPolicies = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache CA policies: $($_.Exception.Message)" -sev Warning
        }

        try {
            $NamedLocations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter

            if ($NamedLocations) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NamedLocations' -Data $NamedLocations
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NamedLocations' -Data $NamedLocations -Count
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($NamedLocations.Count) named locations" -sev Debug
            }
            $NamedLocations = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache named locations: $($_.Exception.Message)" -sev Warning
        }

        try {
            $AuthStrengths = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies' -tenantid $TenantFilter

            if ($AuthStrengths) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthenticationStrengths' -Data $AuthStrengths
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthenticationStrengths' -Data $AuthStrengths -Count
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AuthStrengths.Count) authentication strengths" -sev Debug
            }
            $AuthStrengths = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache authentication strengths: $($_.Exception.Message)" -sev Warning
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached CA data successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Conditional Access data: $($_.Exception.Message)" -sev Error
    }
}
