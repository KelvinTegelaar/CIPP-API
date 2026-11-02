function Get-CIPPIntuneDeployableType {
    <#
    .SYNOPSIS
        The Intune template types Set-CIPPIntunePolicy knows how to deploy.
    .DESCRIPTION
        Must match the labels of Set-CIPPIntunePolicy's dispatch switch; Get-CIPPIntuneDeployableType.Tests.ps1
        reads them back with the AST and fails when the two diverge.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        'AppProtection'
        'AppConfiguration'
        'deviceCompliancePolicies'
        'Admin'
        'Device'
        'Catalog'
        'windowsDriverUpdateProfiles'
        'windowsFeatureUpdateProfiles'
        'windowsQualityUpdatePolicies'
        'hardwareConfigurations'
        'windowsQualityUpdateProfiles'
    )
}
