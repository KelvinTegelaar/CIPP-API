function Test-CIPPCAGapReportOnlyState {
    <#
    .SYNOPSIS
        Lists every policy that is in report-only mode.
    .DESCRIPTION
        A report-only policy logs what would happen but enforces nothing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    foreach ($Policy in @($Context.Policies)) {
        if ($Policy.state -ne 'enabledForReportingButNotEnforced') { continue }
        $Params = @{
            Severity         = 'Info'
            Category         = 'Policy state'
            Title            = 'Policy is in report-only mode'
            Description      = 'The policy records the sign-ins it would have affected but does not act on them, so it provides no protection yet.'
            Remediation      = 'Confirm from the recorded results that the policy behaves as intended, then enforce it.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-report-only'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
