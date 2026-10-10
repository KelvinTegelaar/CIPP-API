function Test-CIPPCAGapResilienceDefaults {
    <#
    .SYNOPSIS
        Flags enabled or report-only policies that disable resilience defaults.
    .DESCRIPTION
        Disabling resilience defaults means users are denied access when their session expires during an
        Entra ID outage.
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
        if ($null -eq $Policy.sessionControls -or $Policy.state -eq 'disabled') { continue }
        if ($Policy.sessionControls.disableResilienceDefaults -ne $true) { continue }

        $Params = @{
            Severity         = 'Medium'
            Category         = 'Resilience'
            Title            = 'Resilience defaults are disabled'
            Description      = 'During a Microsoft sign-in service outage, people covered by this policy lose access as soon as their session expires instead of being allowed to keep working.'
            Remediation      = 'Keep resilience defaults enabled unless a strict need for real-time evaluation outweighs losing access during an outage.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/resilience-defaults'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
