function Set-CIPPDBCacheNetworkAccessFiltering {
    <#
    .SYNOPSIS
        Caches the Global Secure Access web content filtering objects for a tenant: one row per
        filtering profile (with its policy links and the Conditional Access policies using it) and
        one row per filtering policy (with its rules). Each row carries kind = profile | policy.

    .PARAMETER TenantFilter
        The tenant to cache filtering profiles and policies for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $TestResult = Test-CIPPStandardLicense -StandardName 'NetworkAccessFilteringCache' -TenantFilter $TenantFilter -Preset Entra -SkipLog
    if ($TestResult -eq $false) {
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NetworkAccessFiltering' -Data @() -AddCount -ClearOnEmpty
        return
    }

    try {
        $Graph = 'https://graph.microsoft.com/beta/networkAccess'
        # Every networkAccess path except tenantStatus answers 403 until the tenant is onboarded.
        $Status = New-GraphGetRequest -uri "$Graph/tenantStatus" -tenantid $TenantFilter -AsApp $true
        $Rows = [System.Collections.Generic.List[object]]::new()
        if ($Status.onboardingStatus -eq 'onboarded') {
            foreach ($FilteringProfile in @(New-GraphGetRequest -uri "$Graph/filteringProfiles?`$expand=policies(`$expand=policy),conditionalAccessPolicies" -tenantid $TenantFilter -AsApp $true)) {
                $FilteringProfile.PSObject.Properties.Add([psnoteproperty]::new('kind', 'profile'))
                $Rows.Add($FilteringProfile)
            }
            foreach ($Policy in @(New-GraphGetRequest -uri "$Graph/filteringPolicies?`$expand=policyRules" -tenantid $TenantFilter -AsApp $true)) {
                $Policy.PSObject.Properties.Add([psnoteproperty]::new('kind', 'policy'))
                $Rows.Add($Policy)
            }
        }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NetworkAccessFiltering' -Data @($Rows) -AddCount -ClearOnEmpty
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Global Secure Access filtering: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
