function Invoke-CIPPBaselineGlobalSecureAccessProfileTemplate {
    <#
    .SYNOPSIS
        GlobalSecureAccessProfileTemplate executor: deploys the instance's security profile template.
    .DESCRIPTION
        Runs Sync-CIPPGSAFilteringProfile with the templates the prepare hook carried: it creates or
        updates the filtering policies, the security profile and its links, and refuses conflicts.
        Each change is logged; any failed step throws so the engine records an Error.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not $Current.templateBody) { throw 'The security profile template was not loaded.' }
    $Sync = Sync-CIPPGSAFilteringProfile -ProfileTemplate $Current.templateBody -PolicyTemplates $Current.policyTemplates -TenantFilter $TenantFilter
    foreach ($Item in @($Sync.Results)) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message $Item.resultText -Sev ($Item.state -eq 'error' ? 'Error' : 'Info')
    }
    $Failed = @(@($Sync.Results).Where({ $_.state -eq 'error' }).ForEach({ $_.resultText }))
    if ($Failed.Count) { throw "Security profile '$($Current.templateBody.name)' did not deploy fully: $($Failed -join '; ')" }
}
