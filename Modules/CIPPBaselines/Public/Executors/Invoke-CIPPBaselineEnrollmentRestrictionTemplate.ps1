function Invoke-CIPPBaselineEnrollmentRestrictionTemplate {
    <#
    .SYNOPSIS
        EnrollmentRestrictionTemplate executor: creates or updates the template's restriction.
    .DESCRIPTION
        Writes the template the prepare hook resolved through Set-CIPPEnrollmentRestriction - the
        same path the add, edit and deploy endpoint uses. Existing objects are
        targeted by the ids the hook matched, so a restriction is patched in place and a missing
        Android half is created alongside it. Priority is only set on objects this run creates.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Template = $Current.template
    if (-not $Template) { return }

    $SetParams = @{ TenantFilter = $TenantFilter; Settings = $Template; APIName = 'Baselines' }
    $ExistingIds = @($Current.existingIds | Where-Object { $_ })
    if ($ExistingIds.Count -gt 0) { $SetParams.ConfigurationIds = $ExistingIds }
    $null = Set-CIPPEnrollmentRestriction @SetParams
}
