function Invoke-CIPPBaselineSensitivityLabelTemplate {
    <#
    .SYNOPSIS
        SensitivityLabelTemplate executor: deploys the selected sensitivity labels.
    .DESCRIPTION
        Pushes every selected template unconditionally, which is what the classic standard did -
        it called Set-CIPPSensitivityLabel for each template on every remediation run without
        consulting the comparison. That pairs with checkBeforeRun:false on the definition, and it
        matters: the compare only grades presence, so a label whose ENCRYPTION or MARKING settings
        drifted still reads compliant. The unconditional rewrite is what repairs it.

        Set-CIPPSensitivityLabel is upsert - it updates a label of the same name in place and
        creates it otherwise - so there is no create/update branch to make here.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Templates = @($Current.templateBodies | Where-Object { $_ })
    if ($Templates.Count -eq 0) { return }

    foreach ($Template in $Templates) {
        $null = Set-CIPPSensitivityLabel -TenantFilter $TenantFilter -Template $Template -APIName 'Baselines'
    }
}
