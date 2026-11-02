function ConvertTo-CIPPComparableString {
    <#
    .SYNOPSIS
        Produce an order-independent canonical string for a value, for equality comparison.
    .DESCRIPTION
        Recursively serializes scalars, dictionaries/objects (keys sorted), and arrays (elements sorted)
        into a deterministic string. Two values are equal iff their canonical strings match - independent
        of property order or array order, which is the right semantics for DLP locations and the set of
        sensitive information types (order is not meaningful for matching).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return '"' + $Value + '"' }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [string]$Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = foreach ($k in (@($Value.Keys) | Sort-Object)) { '"' + $k + '":' + (ConvertTo-CIPPComparableString -Value $Value[$k]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $parts = foreach ($p in ($Value.PSObject.Properties | Sort-Object Name)) { '"' + $p.Name + '":' + (ConvertTo-CIPPComparableString -Value $p.Value) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @(foreach ($item in $Value) { ConvertTo-CIPPComparableString -Value $item }) | Sort-Object
        return '[' + ($items -join ',') + ']'
    }
    return '"' + ([string]$Value) + '"'
}

function ConvertTo-CIPPDlpComparable {
    <#
    .SYNOPSIS
        Normalize a DLP policy source (template or live policy) + its rules into a comparable param map.
    .DESCRIPTION
        Runs the source through the exact same normalization the deploy path uses - allowlist filtering,
        location normalization, sensitive-information-type conversion (which also strips output-only
        rulePackId), and IncidentReportContent string->array - so a template and the live policy it was
        deployed from collapse to identical structures when nothing has actually drifted.
    .PARAMETER PolicySource
        The policy-level object (a stored template, or a Get-DlpCompliancePolicy result).
    .PARAMETER RuleSource
        The rule collection (template RuleParams, or Get-DlpComplianceRule results).
    .OUTPUTS
        PSCustomObject with Policy (hashtable of normalized policy params) and Rules (ordered map of
        rule name -> hashtable of normalized rule params).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($PolicySource, $RuleSource)

    $Fields = Get-CIPPDlpComplianceFieldList

    $Policy = Format-CIPPCompliancePolicyParams -Source $PolicySource -AllowedFields $Fields.Policy -LocationFields $Fields.Location
    $Policy.Remove('Name') | Out-Null  # identity, not a comparable setting
    # Mirror deploy: an invalid/transient Mode (e.g. PendingDeletion) is never deployed, so it must not
    # register as drift either.
    if ($Policy.ContainsKey('Mode') -and $Policy['Mode'] -notin $Fields.ValidPolicyModes) {
        $Policy.Remove('Mode') | Out-Null
    }

    $Rules = [ordered]@{}
    foreach ($Rule in @($RuleSource) | Where-Object { $_ }) {
        $RuleParams = Format-CIPPCompliancePolicyParams -Source $Rule -AllowedFields $Fields.Rule
        # Mirror deploy: keep only AdvancedRule OR the flat condition params, never both, so the same
        # side is compared that deploy would actually send (see Resolve-CIPPDlpAdvancedRule).
        $RuleParams = Resolve-CIPPDlpAdvancedRule -Source $Rule -RuleParams $RuleParams
        $RuleName = [string]$RuleParams['Name']
        $RuleParams.Remove('Policy') | Out-Null
        $RuleParams.Remove('Name') | Out-Null
        foreach ($SitField in @('ContentContainsSensitiveInformation', 'ExceptIfContentContainsSensitiveInformation')) {
            if ($RuleParams.ContainsKey($SitField)) {
                $RuleParams[$SitField] = @(ConvertTo-CIPPSensitiveInformationType -SensitiveInformation $RuleParams[$SitField])
            }
        }
        if ($RuleParams.ContainsKey('IncidentReportContent') -and $RuleParams['IncidentReportContent'] -is [string]) {
            $RuleParams['IncidentReportContent'] = @($RuleParams['IncidentReportContent'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        # Expand the AdvancedRule JSON string into an object so the canonical comparison string is
        # independent of whitespace and key order (the service may reformat the blob it returns).
        # Unparseable JSON falls back to raw string comparison.
        if ($RuleParams.ContainsKey('AdvancedRule') -and $RuleParams['AdvancedRule'] -is [string]) {
            try { $RuleParams['AdvancedRule'] = $RuleParams['AdvancedRule'] | ConvertFrom-Json -ErrorAction Stop } catch {}
        }
        if (-not [string]::IsNullOrWhiteSpace($RuleName)) { $Rules[$RuleName] = $RuleParams }
    }

    return [pscustomobject]@{ Policy = $Policy; Rules = $Rules }
}

function Compare-CIPPDlpCompliancePolicy {
    <#
    .SYNOPSIS
        Compare a stored DLP template against the live policy + rules in a tenant and report drift.
    .DESCRIPTION
        Normalizes both sides through ConvertTo-CIPPDlpComparable and diffs them field by field
        (policy-level and per-rule, matched by rule name). Returns the overall state and the specific
        differing fields with their expected (template) and current (tenant) values, so callers can
        decide whether to remediate and can surface exactly what differs.
    .PARAMETER TenantFilter
        Target tenant.
    .PARAMETER Template
        The stored template object (already ConvertFrom-Json'd).
    .OUTPUTS
        PSCustomObject: Name, State ('Missing' | 'PendingDeletion' | 'InSync' | 'Drift'), and Differences
        (array of { Scope, Field, Expected, Current }).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TenantFilter,
        [Parameter(Mandatory)] $Template
    )

    $PolicyName = $Template.Name ?? $Template.name

    $LivePolicy = try {
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpCompliancePolicy' -Compliance |
            Where-Object { $_.Name -eq $PolicyName } | Select-Object -First 1
    } catch { $null }

    if (-not $LivePolicy) {
        return [pscustomobject]@{ Name = $PolicyName; State = 'Missing'; Differences = @() }
    }
    if ($LivePolicy.Mode -eq 'PendingDeletion') {
        return [pscustomobject]@{ Name = $PolicyName; State = 'PendingDeletion'; Differences = @() }
    }

    $LiveRules = try {
        @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpComplianceRule' -Compliance |
                Where-Object { $_.ParentPolicyName -eq $PolicyName })
    } catch { @() }

    $Want = ConvertTo-CIPPDlpComparable -PolicySource $Template -RuleSource $Template.RuleParams
    $Have = ConvertTo-CIPPDlpComparable -PolicySource $LivePolicy -RuleSource $LiveRules

    $Differences = [System.Collections.Generic.List[object]]::new()

    # Policy-level diff
    foreach ($Key in (@($Want.Policy.Keys) + @($Have.Policy.Keys) | Select-Object -Unique)) {
        $Expected = if ($Want.Policy.ContainsKey($Key)) { $Want.Policy[$Key] } else { $null }
        $Current = if ($Have.Policy.ContainsKey($Key)) { $Have.Policy[$Key] } else { $null }
        if ((ConvertTo-CIPPComparableString -Value $Expected) -ne (ConvertTo-CIPPComparableString -Value $Current)) {
            $Differences.Add([pscustomobject]@{ Scope = 'Policy'; Field = $Key; Expected = $Expected; Current = $Current })
        }
    }

    # Rule-level diff (only rules the template defines; matched by name)
    foreach ($RuleName in @($Want.Rules.Keys)) {
        if (@($Have.Rules.Keys) -notcontains $RuleName) {
            $Differences.Add([pscustomobject]@{ Scope = "Rule '$RuleName'"; Field = '(entire rule)'; Expected = 'present'; Current = 'missing' })
            continue
        }
        $WantRule = $Want.Rules[$RuleName]
        $HaveRule = $Have.Rules[$RuleName]
        foreach ($Key in (@($WantRule.Keys) + @($HaveRule.Keys) | Select-Object -Unique)) {
            $Expected = if ($WantRule.ContainsKey($Key)) { $WantRule[$Key] } else { $null }
            $Current = if ($HaveRule.ContainsKey($Key)) { $HaveRule[$Key] } else { $null }
            if ((ConvertTo-CIPPComparableString -Value $Expected) -ne (ConvertTo-CIPPComparableString -Value $Current)) {
                $Differences.Add([pscustomobject]@{ Scope = "Rule '$RuleName'"; Field = $Key; Expected = $Expected; Current = $Current })
            }
        }
    }

    $State = if ($Differences.Count -eq 0) { 'InSync' } else { 'Drift' }
    return [pscustomobject]@{ Name = $PolicyName; State = $State; Differences = @($Differences) }
}
