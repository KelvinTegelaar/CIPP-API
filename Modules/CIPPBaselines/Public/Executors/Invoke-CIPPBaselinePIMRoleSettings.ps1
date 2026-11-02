function Invoke-CIPPBaselinePIMRoleSettings {
    <#
    .SYNOPSIS
        PIMRoleSettings executor: patches the differing policy rules of each drifted role.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not (Test-CIPPPIMRoleSettingsFloor -Settings $Current.templateSettings).Valid) {
        throw "PIM role settings template '$($Current.templateName)' is below the secure floor and was not applied."
    }

    $Attempted = 0
    $Failed = 0
    $Missing = [System.Collections.Generic.List[string]]::new()
    foreach ($State in @($Current.driftedRoles)) {
        if (-not $State) { continue }
        if (-not $State.PolicyId) {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "PIMRoleSettings: no PIM policy exists for $($State.Role); cannot apply the template to it." -sev Warning
            $Missing.Add("$($State.Role)")
            continue
        }
        $Attempted++
        $Results = @(Set-CIPPPIMRoleSettings -TenantFilter $TenantFilter -PolicyId $State.PolicyId -DesiredRules $State.Desired -CurrentRules $State.Rules -RoleName $State.Role -APIName 'Baselines')
        if ($Results.Where({ $_.Success -ne $true }).Count -gt 0) { $Failed++ }
    }

    if ($Attempted -eq 0 -and $Missing.Count -gt 0) {
        throw "No PIM policy exists for $($Missing -join ', '); PIM role settings template '$($Current.templateName)' cannot be applied."
    }
    if ($Attempted -gt 0 -and $Failed -eq $Attempted) {
        throw "Failed to apply PIM role settings template '$($Current.templateName)' to every drifted role."
    }
}
