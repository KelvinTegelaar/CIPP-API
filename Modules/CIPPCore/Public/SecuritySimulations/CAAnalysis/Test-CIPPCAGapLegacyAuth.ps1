function Test-CIPPCAGapLegacyAuth {
    <#
    .SYNOPSIS
        Checks that legacy authentication (Exchange ActiveSync / Other clients) is blocked.
    .DESCRIPTION
        Tenant-wide: when no enabled policy blocks the legacy client types, a Critical finding is raised
        with the block-legacy-authentication template as the fix.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    $TargetsLegacy = {
        param($P)
        $Types = @($P.conditions.clientAppTypes)
        ($Types -contains 'exchangeActiveSync') -or ($Types -contains 'other')
    }

    $BlocksLegacy = @($Context.Enabled | Where-Object { (& $TargetsLegacy $_) -and (@($_.grantControls.builtInControls) -contains 'block') }).Count -gt 0
    if ($BlocksLegacy) { return @() }

    $Params = @{
        Severity         = 'Critical'
        Category         = 'Older sign-in methods'
        Title            = 'Older sign-in methods that cannot use multifactor authentication are still allowed'
        Description      = 'No enforced policy stops the older mail and client protocols that cannot perform multifactor authentication. A stolen password is enough to sign in through them, which is why they are the usual route for password-spray attacks.'
        Remediation      = 'Block the older sign-in methods (Exchange ActiveSync and other legacy clients) for every user.'
        CaTemplate       = "$($Context.Data.Reference.templates.blockLegacyAuth)"
        DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-block-legacy-authentication'
    }
    $Findings.Add((New-CIPPCAGapFinding @Params))

    foreach ($Policy in @($Context.Policies)) {
        if ($Policy.state -eq 'disabled') { continue }
        if (-not (& $TargetsLegacy $Policy)) { continue }
        if (@($Policy.grantControls.builtInControls) -contains 'block') { continue }
        $Params = @{
            Severity         = 'Medium'
            Category         = 'Older sign-in methods'
            Title            = 'A policy covers older sign-in methods without blocking them'
            Description      = 'This policy applies to older sign-in methods but grants access instead of blocking it. Those methods cannot complete multifactor authentication, so the requirement this policy sets can never be met and the policy adds no protection.'
            Remediation      = 'Change this policy to block the older sign-in methods, or rely on a dedicated policy that blocks them for every user.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-block-legacy-authentication'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
