function Get-CIPPBaselineGlobalSecureAccessCompliantNetworkState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessCompliantNetwork: grades the tenant setup, the
        client deployment and the Conditional Access policy as flat booleans.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $V = $Item.Variables
    if ($V -is [System.Collections.IDictionary]) { $V = [PSCustomObject]$V }
    $DeployWindows = $V.deployWindows -ne $false
    $DeployMacOS = $V.deployMacOS -ne $false
    $Enforce = $V.enforce -eq $true
    $RoleIds = @($V.excludeAdminRoles | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ } | Sort-Object -Unique)
    $UserRefs = @($V.excludeUsers | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
    $GroupRefs = @($V.excludeGroups | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })

    $State = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess' | Where-Object { $_ }) | Select-Object -First 1
    if (-not $State) { return @{ Current = $null } }

    $Locations = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'NamedLocations' -CollectorType 'ConditionalAccessPolicies')
    $Location = @($Locations | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.compliantNetworkNamedLocation' }) | Select-Object -First 1
    $TrafficProfile = @($State.profiles | Where-Object { $_.trafficForwardingType -eq 'm365' -and $_.isCustomProfile -ne $true }) | Select-Object -First 1
    $Links = @($TrafficProfile.policies | Where-Object { $_ })

    $Expected = [ordered]@{
        onboarded                       = $true
        microsoftProfileEnabled         = $true
        microsoftPolicyGroupsEnabled    = $true
        profileAssignedToAllUsers       = $true
        signalingEnabled                = $true
        compliantNetworkLocationPresent = $true
    }
    $Current = [ordered]@{
        onboarded                       = $State.onboarded -eq $true
        microsoftProfileEnabled         = $TrafficProfile.state -eq 'enabled'
        microsoftPolicyGroupsEnabled    = $Links.Count -gt 0 -and @($Links | Where-Object { $_.state -ne 'enabled' }).Count -eq 0
        profileAssignedToAllUsers       = $TrafficProfile.appRoleAssignmentRequired -eq $false
        signalingEnabled                = $State.signalingStatus -eq 'enabled'
        compliantNetworkLocationPresent = $null -ne $Location
    }

    if ($DeployWindows) {
        $Apps = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneMobileApps')
        $Expected.windowsAppDeployed = $true
        $Current.windowsAppDeployed = @($Apps | Where-Object { $_.displayName -eq 'Global Secure Access Client (Windows)' }).Count -gt 0
    }
    if ($DeployMacOS) {
        $Scripts = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneMacOSScripts' -CollectorType 'IntuneScripts')
        $Catalog = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')
        $Configs = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneDeviceConfigurations' -CollectorType 'IntunePolicies')
        $Expected.macOSScriptDeployed = $true
        $Current.macOSScriptDeployed = @($Scripts | Where-Object { $_.displayName -eq 'Global Secure Access Client (macOS)' }).Count -gt 0
        $Expected.macOSSystemExtensionsPolicyDeployed = $true
        $Current.macOSSystemExtensionsPolicyDeployed = @($Catalog | Where-Object { $_.name -eq 'Global Secure Access - macOS System Extensions' }).Count -gt 0
        $Expected.macOSTransparentProxyProfileDeployed = $true
        $Current.macOSTransparentProxyProfileDeployed = @($Configs | Where-Object { $_.displayName -eq 'Global Secure Access - macOS Transparent Proxy' }).Count -gt 0
        $Expected.macOSClientSettingsProfileDeployed = $true
        $Current.macOSClientSettingsProfileDeployed = @($Configs | Where-Object { $_.displayName -eq 'Global Secure Access - macOS Client Settings' }).Count -gt 0
    }

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies')
    $Policy = @($Policies | Where-Object { $_.displayName -eq 'CIPP: Require compliant network (Global Secure Access)' }) | Select-Object -First 1
    $Expected.policyPresent = $true
    $Current.policyPresent = $null -ne $Policy
    $Expected.policyState = if ($Enforce) { 'enabled' } else { 'enabledForReportingButNotEnforced' }
    $Current.policyState = "$($Policy.state)"
    $LiveRoles = @($Policy.conditions.users.excludeRoles)
    $Expected.policyExcludedRoles = $RoleIds -join ','
    $Current.policyExcludedRoles = @($RoleIds | Where-Object { $LiveRoles -contains $_ }) -join ','
    if ($UserRefs.Count -gt 0 -or $GroupRefs.Count -gt 0) {
        $Users = if ($UserRefs.Count -gt 0) { @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users') } else { @() }
        $Groups = if ($GroupRefs.Count -gt 0) { @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups') } else { @() }
        $ExcludedIds = @($Policy.conditions.users.excludeUsers) + @($Policy.conditions.users.excludeGroups)
        $Resolved = @($UserRefs | ForEach-Object { $Ref = $_; ($Users | Where-Object { $_.userPrincipalName -eq $Ref -or $_.displayName -eq $Ref -or $_.id -eq $Ref } | Select-Object -First 1).id }) +
        @($GroupRefs | ForEach-Object { $Ref = $_; ($Groups | Where-Object { $_.displayName -eq $Ref -or $_.id -eq $Ref } | Select-Object -First 1).id })
        $Expected.policyExclusionsPresent = $true
        $Current.policyExclusionsPresent = @($Resolved | Where-Object { -not $_ -or $ExcludedIds -notcontains $_ }).Count -eq 0
    }

    $CurrentObject = [PSCustomObject]$Current
    $PolicyDrift = @($Expected.Keys | Where-Object { $_ -like 'policy*' -and "$($Expected[$_])" -ne "$($Current[$_])" }).Count -gt 0
    $CurrentObject | Add-Member -NotePropertyName policyDrift -NotePropertyValue $PolicyDrift
    $CurrentObject | Add-Member -NotePropertyName compliantNetworkLocationId -NotePropertyValue "$($Location.id)"

    @{ Expected = [PSCustomObject]$Expected; Current = $CurrentObject }
}
