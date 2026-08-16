function Invoke-CIPPBaselineRetentionCompliancePolicyTemplate {
    <#
    .SYNOPSIS
        RetentionCompliancePolicyTemplate executor: deploys the selected retention policies.
    .DESCRIPTION
        Pushes every selected template unconditionally, which is what the classic standard did -
        it called Set-CIPPRetentionCompliancePolicy for each template on every remediation run
        without consulting the comparison. That pairs with checkBeforeRun:false on the definition:
        the compare only grades presence, so a policy whose RULES or LOCATIONS drifted still reads
        compliant, and the unconditional rewrite is what repairs it.

        Set-CIPPRetentionCompliancePolicy is upsert over both the policy and its rules, so there
        is no create/update branch to make here.
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
        $null = Set-CIPPRetentionCompliancePolicy -TenantFilter $TenantFilter -Template $Template -APIName 'Baselines'
    }
}
