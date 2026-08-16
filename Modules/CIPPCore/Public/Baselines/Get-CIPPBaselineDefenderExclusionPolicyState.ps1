function Get-CIPPBaselineDefenderExclusionPolicyState {
    <#
    .SYNOPSIS
        Prepare hook for DefenderExclusionPolicy: the 'Default AV Exclusion Policy' settings
        catalog policy.
    .DESCRIPTION
        Grades the three exclusion collections (extensions, paths, processes) as SORTED sets
        against the cached policy's simpleSettingCollectionValues - the classic compared
        sorted arrays with Compare-Object, so order never matters and any missing or extra
        entry is drift.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')) {
        return @{ Current = $null }
    }
    $Policy = @($Policies | Where-Object { "$($_.name)" -eq 'Default AV Exclusion Policy' }) | Select-Object -First 1

    $V = $Item.Variables
    $ExpectedExtensions = @(("$($V.excludedExtensions)" -replace ' ', '') -split ',' | Where-Object { $_ } | Sort-Object)
    $ExpectedPaths = @("$($V.excludedPaths)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
    $ExpectedProcesses = @("$($V.excludedProcesses)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)

    $CurrentExtensions = @()
    $CurrentPaths = @()
    $CurrentProcesses = @()
    foreach ($Setting in @($Policy.settings)) {
        $Instance = $Setting.settingInstance
        switch ("$($Instance.settingDefinitionId)") {
            'device_vendor_msft_policy_config_defender_excludedextensions' {
                $CurrentExtensions = @($Instance.simpleSettingCollectionValue | ForEach-Object { "$($_.value)" } | Sort-Object)
            }
            'device_vendor_msft_policy_config_defender_excludedpaths' {
                $CurrentPaths = @($Instance.simpleSettingCollectionValue | ForEach-Object { "$($_.value)" } | Sort-Object)
            }
            'device_vendor_msft_policy_config_defender_excludedprocesses' {
                $CurrentProcesses = @($Instance.simpleSettingCollectionValue | ForEach-Object { "$($_.value)" } | Sort-Object)
            }
        }
    }

    $Current = [PSCustomObject]@{
        policyExists       = ($null -ne $Policy)
        excludedExtensions = @($CurrentExtensions)
        excludedPaths      = @($CurrentPaths)
        excludedProcesses  = @($CurrentProcesses)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'policyId' -NotePropertyValue "$($Policy.id)"

    @{
        Expected = [PSCustomObject]@{
            policyExists       = $true
            excludedExtensions = @($ExpectedExtensions)
            excludedPaths      = @($ExpectedPaths)
            excludedProcesses  = @($ExpectedProcesses)
        }
        Current  = $Current
    }
}
