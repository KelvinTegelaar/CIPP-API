function Get-CIPPIntunePolicyAssignments {
    <#
    .SYNOPSIS
        Gets the assignments for an existing Intune policy.
    .PARAMETER PolicyId
        The Intune policy ID.
    .PARAMETER TemplateType
        The template type (Device, Catalog, Admin, deviceCompliancePolicies, AppProtection,
        windowsDriverUpdateProfiles, windowsFeatureUpdateProfiles, windowsQualityUpdatePolicies,
        windowsQualityUpdateProfiles).
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
            $OdataType = if ($ExistingPolicy) { $ExistingPolicy.'@odata.type' -replace '#microsoft.graph.', '' } else { $null }
            if (-not $OdataType) { return $null }
            $TypeUrl = if ($OdataType -eq 'windowsInformationProtectionPolicy') { 'windowsInformationProtectionPolicies' } else { "${OdataType}s" }
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
        default { return $null }
    }

    $Uri = "https://graph.microsoft.com/beta/$PlatformType/$TypeUrl('$PolicyId')/assignments"
    return New-GraphGetRequest -uri $Uri -tenantid $TenantFilter
}
