function Invoke-CIPPBaselineSensitiveInfoTypeTemplate {
    <#
    .SYNOPSIS
        SensitiveInfoTypeTemplate executor: deploys the SITs that are missing or drifted.
    .DESCRIPTION
        Unlike the other template families this one is selective, and deliberately so. It writes
        only the templates the prepare hook found Missing or Drift - the same subset the classic
        standard remediated. Templates that came back Invalid are broken TEMPLATES, not broken
        tenants, so deploying them would fail; templates that came back BuiltIn collide with a
        Microsoft SIT that cannot be modified. Both are reported and left alone.

        Set-CIPPSensitiveInfoType reports its outcome in its return string rather than by
        throwing, which is why the result is matched rather than trusted. Anything that is not
        Created or Updated is a failure and is logged as one - the classic did the same.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Templates = @($Current.remediableTemplates | Where-Object { $_ })
    if ($Templates.Count -eq 0) { return }

    foreach ($Template in $Templates) {
        $Result = Set-CIPPSensitiveInfoType -TenantFilter $TenantFilter -Template $Template -APIName 'Baselines'
        if ("$Result" -match '^(Created|Updated)') {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Remediated Sensitive Information Type '$($Template.Name)': $Result" -Sev 'Info'
        } else {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$Result" -Sev 'Error'
        }
    }
}
