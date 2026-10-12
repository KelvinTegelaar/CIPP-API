function Get-CIPPBaselineDeployCheckChromeExtensionState {
    <#
    .SYNOPSIS
        Prepare hook for DeployCheckChromeExtension: the Check by CyberDrain Win32 app.
    .DESCRIPTION
        Grades PRESENCE of the 'Check by CyberDrain - Browser Extension' Win32 app, exactly
        what the classic reported. Settings drift is the EXECUTOR's job: the app description
        carries a config fingerprint and the executor redeploys only when it changes, so the
        definition runs checkBeforeRun:false and remediation self-gates - grading the hash
        here would change what the classic surfaced as drift.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Apps = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneMobileApps')
    if ($Apps.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneMobileApps')) {
        return @{ Current = $null }
    }
    # The cache $select drops @odata.type on some rows, so match on the CIPP-authored
    # display name alone - it is unique to this deployment.
    $App = @($Apps | Where-Object { "$($_.displayName)" -eq 'Check by CyberDrain - Browser Extension' }) | Select-Object -First 1

    @{
        Expected = [PSCustomObject]@{ appDeployed = $true }
        Current  = [PSCustomObject]@{ appDeployed = ($null -ne $App) }
    }
}
