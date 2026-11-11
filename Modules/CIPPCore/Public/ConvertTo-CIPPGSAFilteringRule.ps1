function ConvertTo-CIPPGSAFilteringRule {
    <#
    .SYNOPSIS
        Validates Global Secure Access filtering rules and returns them in Graph shape.
    .DESCRIPTION
        Each rule needs a name (unique), a ruleType of webCategory, fqdn or url, and at least one
        destination, given as a name/value or a Graph destination object. Destinations are trimmed,
        de-duplicated and sorted. Returns Rules and Errors; callers refuse the input when Errors has
        anything in it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([object[]]$Rules)

    $RuleTypes = @{
        webCategory = @{ Rule = '#microsoft.graph.networkaccess.webCategoryFilteringRule'; Destination = '#microsoft.graph.networkaccess.webCategory'; Property = 'name' }
        fqdn        = @{ Rule = '#microsoft.graph.networkaccess.fqdnFilteringRule'; Destination = '#microsoft.graph.networkaccess.fqdn'; Property = 'value' }
        url         = @{ Rule = '#microsoft.graph.networkaccess.urlDestinationFilteringRule'; Destination = '#microsoft.graph.networkaccess.url'; Property = 'value' }
    }
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Output = [System.Collections.Generic.List[object]]::new()
    $RuleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $InputRules = @($Rules).Where({ $null -ne $_ })
    if ($InputRules.Count -eq 0) { $Errors.Add('at least one rule is required') }
    foreach ($Rule in $InputRules) {
        $RuleName = ([string]$Rule.name).Trim()
        $Type = $RuleTypes[[string]$Rule.ruleType]
        $Values = @(@($Rule.destinations).ForEach({ if ($_ -is [string]) { $_ } else { $_.name ?? $_.value } }).Where({ -not [string]::IsNullOrWhiteSpace($_) }).ForEach({ $_.Trim() }) | Sort-Object -Unique)
        if (-not $RuleName) { $Errors.Add('every rule needs a name'); continue }
        if (-not $RuleNames.Add($RuleName)) { $Errors.Add("rule name '$RuleName' is used twice") }
        if (-not $Type) { $Errors.Add("rule '$RuleName' has an unknown type '$($Rule.ruleType)'; use webCategory, fqdn or url"); continue }
        if ($Values.Count -eq 0) { $Errors.Add("rule '$RuleName' has no destinations"); continue }
        $Output.Add([ordered]@{
                '@odata.type' = $Type.Rule
                name          = $RuleName
                ruleType      = [string]$Rule.ruleType
                destinations  = @($Values.ForEach({ [ordered]@{ '@odata.type' = $Type.Destination; $Type.Property = $_ } }))
            })
    }
    [pscustomobject]@{ Rules = @($Output); Errors = @($Errors) }
}
