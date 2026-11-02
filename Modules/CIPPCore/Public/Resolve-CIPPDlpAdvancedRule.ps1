function Resolve-CIPPDlpAdvancedRule {
    <#
    .SYNOPSIS
        Enforce the AdvancedRule vs simple-mode condition exclusivity on a filtered DLP rule param set.
    .DESCRIPTION
        A DLP rule built with Purview's Advanced Rule editor carries its entire condition tree in the
        single AdvancedRule JSON blob and leaves the flat simple-mode condition properties empty; a
        simple-mode rule is the reverse. New-/Set-DlpComplianceRule reject AdvancedRule combined with
        any simple-mode condition/exception parameter, so every code path that builds rule params
        (template capture, deploy, drift comparison) must end up with one or the other, never both.

        Which side is authoritative comes from the source's IsAdvancedRule flag (Get-DlpComplianceRule
        emits it, but the allowlist strips it from stored params - hence reading it off the unfiltered
        source). Without the flag - e.g. a stored template, where a captured AdvancedRule is always
        deliberate - a populated AdvancedRule wins. AdvancedRule is normalized to the JSON string the
        cmdlets expect; it is kept as a string in stored templates too, so a deep condition tree can
        never be truncated by the template's ConvertTo-Json -Depth limit.
    .PARAMETER Source
        The unfiltered rule object (Get-DlpComplianceRule output, stored template rule, or request
        body), used to read IsAdvancedRule.
    .PARAMETER RuleParams
        The allowlist-filtered rule parameter hashtable to fix up. Modified in place and returned.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Source,
        [Parameter(Mandatory)] [hashtable] $RuleParams
    )

    if (-not $RuleParams.ContainsKey('AdvancedRule')) { return $RuleParams }

    # ConvertFrom-Json yields a real boolean, but a hand-edited template may carry 'False' as a string;
    # string-compare handles both. An absent flag means AdvancedRule was stored deliberately -> advanced.
    $Flag = $Source.PSObject.Properties['IsAdvancedRule']
    $IsAdvanced = -not ($null -ne $Flag -and $null -ne $Flag.Value -and "$($Flag.Value)" -eq 'False')

    if (-not $IsAdvanced) {
        # Simple-mode rule: the flat condition parameters are authoritative. Get-DlpComplianceRule can
        # still emit an AdvancedRule serialization of those same conditions - it must not be captured,
        # deployed, or drift-compared alongside them.
        $RuleParams.Remove('AdvancedRule') | Out-Null
        return $RuleParams
    }

    $Fields = Get-CIPPDlpComplianceFieldList
    foreach ($Condition in $Fields.RuleConditions) {
        if ($RuleParams.ContainsKey($Condition)) { $RuleParams.Remove($Condition) | Out-Null }
    }

    # The cmdlets take AdvancedRule as a JSON string (Get-* already returns it that way); serialize a
    # hand-authored nested object. -Depth 100 because condition trees nest far past the default.
    if ($RuleParams['AdvancedRule'] -isnot [string]) {
        $RuleParams['AdvancedRule'] = ConvertTo-Json -InputObject $RuleParams['AdvancedRule'] -Depth 100 -Compress
    }
    return $RuleParams
}
