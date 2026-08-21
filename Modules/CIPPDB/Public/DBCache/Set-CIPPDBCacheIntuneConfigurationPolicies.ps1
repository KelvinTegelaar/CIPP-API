function Set-CIPPDBCacheIntuneConfigurationPolicies {
    <#
    .SYNOPSIS
        Caches Intune settings catalog policies (with settings and assignments) for a tenant.

    .DESCRIPTION
        Thin single-family collector for the IntuneConfigurationPolicies cache type, which the
        Set-CIPPDBCacheIntunePolicies umbrella also writes on its schedule. It exists so the
        convention lookup (Set-CIPPDBCache<Type>) resolves for collect-on-miss and for the
        post-remediation refresh - the umbrella cannot be named after every type it writes.
        Same URI as the umbrella's family entry, so both writers produce the same row shape.

    .PARAMETER TenantFilter
        The tenant to cache settings catalog policies for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneConfigurationPoliciesCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping configuration policies cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune configuration policies' -sev Debug
        $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$expand=assignments,settings&$top=1000' -tenantid $TenantFilter
        if (-not $Policies) { $Policies = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies' -Data @($Policies) -AddCount -ClearOnEmpty

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Policies | Measure-Object).Count) configuration policies" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache configuration policies: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
