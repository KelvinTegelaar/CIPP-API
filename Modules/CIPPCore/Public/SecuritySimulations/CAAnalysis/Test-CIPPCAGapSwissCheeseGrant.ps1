function Test-CIPPCAGapSwissCheeseGrant {
    <#
    .SYNOPSIS
        Reviews policies whose grant controls are combined with the OR operator.
    .DESCRIPTION
        With OR, only the weakest listed control has to be satisfied.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Groups = $Context.Data.Reference.equivalentStrengthGroups
    $Labels = $Context.Data.Reference.grantControlLabels

    foreach ($Policy in @($Context.Policies)) {
        $Grant = $Policy.grantControls
        if (-not $Grant.present -or $Grant.operator -ne 'OR') { continue }

        $Controls = @($Grant.builtInControls | Where-Object { $_ -ne 'block' })
        if ($Controls.Count -le 1) { continue }

        $DistinctGroups = @($Controls | ForEach-Object {
                $ControlName = $_
                $Group = $Groups.$ControlName
                if ($Group) { "$Group" } else { "unique:$ControlName" }
            } | Select-Object -Unique)
        $SoleGroup = if ($DistinctGroups.Count -eq 1) { $DistinctGroups[0] } else { $null }
        $IsManagedAccessOnly = @($DistinctGroups | Where-Object { $_ -ne 'DeviceTrust' -and $_ -ne 'AppProtection' }).Count -eq 0
        $IsAcceptedEquivalentOr = ($null -ne $SoleGroup) -or $IsManagedAccessOnly

        $LabelList = @($Controls | ForEach-Object {
                $ControlName = $_
                $Label = $Labels.$ControlName
                if ($Label) { "$Label" } else { $ControlName }
            })
        $Joined = $LabelList -join ' or '

        if ($IsAcceptedEquivalentOr) {
            $SpansBothGroups = ($null -eq $SoleGroup) -and $IsManagedAccessOnly
            $Explanation = if ($SpansBothGroups) {
                'Accepting either a managed device or a protected app is the pattern Microsoft recommends for mixed corporate and personal devices; both paths prove the access is managed.'
            } elseif ($SoleGroup -eq 'DeviceTrust') {
                'Accepting either a compliant device or a hybrid-joined device is a recommended way to require a managed device across cloud-managed and domain-joined estates; neither path is weaker than the other.'
            } else {
                'Accepting either an approved client app or an app protection policy is the recommended pattern for protecting data in mobile apps; both paths provide equivalent protection.'
            }
            $Params = @{
                Severity         = 'Info'
                Category         = 'Grant requirements'
                Title            = 'Policy accepts either of two equally strong requirements'
                Description      = "This policy is satisfied by $Joined. Because these requirements are of equal strength, there is no weaker path for an attacker to choose. $Explanation"
                Remediation      = 'No change needed. If multifactor authentication is meant to apply on top of these device or app requirements, make sure a separate policy enforces it.'
                AffectedPolicies = @($Policy.displayName)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-grant'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
            continue
        }

        $Params = @{
            Severity         = 'High'
            Category         = 'Grant requirements'
            Title            = 'Policy is satisfied by the weakest of several requirements'
            Description      = "This policy accepts $Joined. Because the requirements differ in strength and any one of them is enough, an attacker only needs to meet the easiest one and the stronger ones add nothing."
            Remediation      = 'Require all of these controls together, or split them into separate policies that each enforce a single requirement.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-grant'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
