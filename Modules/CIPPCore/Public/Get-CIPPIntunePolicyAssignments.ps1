function Get-CIPPIntunePolicyAssignments {
    <#
    .SYNOPSIS
        Gets the assignments for an existing Intune policy.
    .PARAMETER PolicyId
        The Intune policy ID.
    .PARAMETER TemplateType
        The template type (Device, Catalog, Admin, deviceCompliancePolicies, AppProtection,
        windowsDriverUpdateProfiles, windowsFeatureUpdateProfiles, windowsQualityUpdatePolicies,
        windowsQualityUpdateProfiles, hardwareConfigurations).
    .PARAMETER TenantFilter
        The tenant to query.
    .PARAMETER ExistingPolicy
        The existing policy object. Required for AppProtection to determine the odata subtype.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$TemplateType,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        $ExistingPolicy
    )

    switch ($TemplateType) {
        'Device' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'deviceConfigurations'
        }
        'Catalog' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'configurationPolicies'
        }
        'Admin' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'groupPolicyConfigurations'
        }
        'deviceCompliancePolicies' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'deviceCompliancePolicies'
        }
        'AppProtection' {
            $PlatformType = 'deviceAppManagement'
            # App Protection spans several collections and assignments live under the concrete one.
            # A policy read from its own collection has no @odata.type - Graph only emits it for
            # reads through managedAppPolicies - so resolve from whatever the payload does carry.
            $TypeUrl = if ($ExistingPolicy) { Get-CIPPAppProtectionPolicyUrl -Policy $ExistingPolicy } else { $null }
            if (-not $TypeUrl) { return $null }
        }
        'windowsDriverUpdateProfiles' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'windowsDriverUpdateProfiles'
        }
        'windowsFeatureUpdateProfiles' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'windowsFeatureUpdateProfiles'
        }
        'windowsQualityUpdatePolicies' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'windowsQualityUpdatePolicies'
        }
        'windowsQualityUpdateProfiles' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'windowsQualityUpdateProfiles'
        }
        'hardwareConfigurations' {
            $PlatformType = 'deviceManagement'
            $TypeUrl = 'hardwareConfigurations'
        }
        default { return $null }
    }

    $Uri = "https://graph.microsoft.com/beta/$PlatformType/$TypeUrl('$PolicyId')/assignments"
    return New-GraphGetRequest -uri $Uri -tenantid $TenantFilter
}
