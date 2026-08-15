function Set-CIPPDBCacheHomeRealmDiscoveryPolicy {
    <#
    .SYNOPSIS
        Caches home realm discovery policies for a tenant

    .DESCRIPTION
        Caches all home realm discovery policies. Each cached row keeps the raw policy properties
        and additionally carries a normalized alternateIdLoginEnabled field parsed from the
        policy definition JSON (HomeRealmDiscoveryPolicy.AlternateIdLogin.Enabled).

    .PARAMETER TenantFilter
        The tenant to cache home realm discovery policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching home realm discovery policies' -sev Debug

        $Policies = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/homeRealmDiscoveryPolicies' -tenantid $TenantFilter)

        $CachedPolicies = foreach ($Policy in $Policies) {
            $Definition = if ($Policy.definition) {
                ($Policy.definition | Select-Object -First 1) | ConvertFrom-Json -ErrorAction SilentlyContinue
            } else {
                $null
            }
            $AlternateIdLoginEnabledRaw = $Definition.HomeRealmDiscoveryPolicy.AlternateIdLogin.Enabled
            $AlternateIdLoginEnabled = if ($null -eq $AlternateIdLoginEnabledRaw) { $false } else { [bool]$AlternateIdLoginEnabledRaw }

            # Keep the raw row (id, displayName, isOrganizationDefault, definition, etc.) and project the normalized field onto it
            $Policy | Add-Member -MemberType NoteProperty -Name 'alternateIdLoginEnabled' -Value $AlternateIdLoginEnabled -Force
            $Policy
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'HomeRealmDiscoveryPolicy' -Data @($CachedPolicies) -AddCount
        $CachedPolicies = $null
        $Policies = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached home realm discovery policies successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache home realm discovery policies: $($_.Exception.Message)" -sev Error
    }
}
