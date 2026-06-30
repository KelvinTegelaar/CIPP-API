function ConvertTo-CIPPSitComparable {
    <#
    .SYNOPSIS
        Reduce a SIT rule pack XML to a semantic, comparable structure (ignoring volatile ids/versions).
    .DESCRIPTION
        A rule pack XML carries GUIDs (RulePack/Publisher/Entity/Regex ids) and a version that change
        between deploys and are assigned by Microsoft, so a raw XML compare always looks like drift. This
        extracts only the meaningful content per entity - name, description, recommended confidence,
        patterns proximity, and each pattern's confidence level with its resolved regex/keyword content -
        keyed by entity name. Parsing is namespace-agnostic (local-name()) so the 2011 and 2018 schemas
        both work.
    .OUTPUTS
        Hashtable of entityName -> ordered hashtable { confidence, proximity, description, patterns }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][string]$Xml)

    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Xml)) { return $result }
    try { [xml]$doc = $Xml } catch { return $result }

    # Resolve referenced detection elements: regex id -> pattern text, keyword id -> sorted terms.
    $regexMap = @{}
    foreach ($r in $doc.SelectNodes("//*[local-name()='Regex']")) {
        if ($r.id) { $regexMap[[string]$r.id] = ([string]$r.InnerText).Trim() }
    }
    $keywordMap = @{}
    foreach ($k in $doc.SelectNodes("//*[local-name()='Keyword']")) {
        $terms = @($k.SelectNodes(".//*[local-name()='Term']") | ForEach-Object { ([string]$_.InnerText).Trim() }) | Sort-Object
        if ($k.id) { $keywordMap[[string]$k.id] = ($terms -join '|') }
    }

    # entity id -> localized name/description
    $resMap = @{}
    foreach ($res in $doc.SelectNodes("//*[local-name()='Resource']")) {
        if (-not $res.idRef) { continue }
        $nameNode = $res.SelectSingleNode("*[local-name()='Name']")
        $descNode = $res.SelectSingleNode("*[local-name()='Description']")
        $resMap[[string]$res.idRef] = @{
            Name        = if ($nameNode) { ([string]$nameNode.InnerText).Trim() } else { '' }
            Description = if ($descNode) { ([string]$descNode.InnerText).Trim() } else { '' }
        }
    }

    foreach ($ent in $doc.SelectNodes("//*[local-name()='Entity']")) {
        $eid = [string]$ent.id
        $name = if ($resMap.ContainsKey($eid) -and $resMap[$eid].Name) { $resMap[$eid].Name } else { $eid }

        $patterns = @(foreach ($p in $ent.SelectNodes("*[local-name()='Pattern']")) {
                $matches = @($p.SelectNodes(".//*[@idRef]") | ForEach-Object {
                        $ref = [string]$_.idRef
                        if ($regexMap.ContainsKey($ref)) { "regex:$($regexMap[$ref])" }
                        elseif ($keywordMap.ContainsKey($ref)) { "keyword:$($keywordMap[$ref])" }
                        else { "ref:$ref" }
                    }) | Sort-Object
                [ordered]@{ level = [string]$p.confidenceLevel; matches = @($matches) }
            })

        $result[$name] = [ordered]@{
            confidence  = [string]$ent.recommendedConfidence
            proximity   = [string]$ent.patternsProximity
            description = if ($resMap.ContainsKey($eid)) { $resMap[$eid].Description } else { '' }
            patterns    = @($patterns)
        }
    }
    return $result
}

function Compare-CIPPSensitiveInfoType {
    <#
    .SYNOPSIS
        Compare a stored SIT template against the live custom SIT in a tenant and report drift.
    .DESCRIPTION
        Resolves the template's intended rule pack XML (advanced FileDataBase64, or synthesized from a
        simple Pattern), fetches the live SIT's rule pack XML, reduces both to a semantic structure via
        ConvertTo-CIPPSitComparable, and diffs each templated entity (matched by name). Returns the state
        and the specific differing fields with expected (template) vs current (tenant) values.
    .OUTPUTS
        PSCustomObject: Name, State ('Missing' | 'BuiltIn' | 'Invalid' | 'InSync' | 'Drift'), Differences.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TenantFilter,
        [Parameter(Mandatory)] $Template
    )

    $Name = $Template.Name ?? $Template.name

    # Resolve the template's intended rule pack XML.
    $WantXml = $null
    if ($Template.FileDataBase64) {
        try { $Bytes = [System.Convert]::FromBase64String($Template.FileDataBase64) } catch { $Bytes = $null }
        if ($Bytes) {
            $WantXml = [System.Text.Encoding]::Unicode.GetString($Bytes)
            if ($WantXml -notmatch '<RulePackage') { $WantXml = [System.Text.Encoding]::UTF8.GetString($Bytes) }
        }
    } elseif ($Template.Pattern) {
        $WantXml = New-CIPPSitRulePackXml `
            -Name $Name `
            -Description ($Template.Description ?? '') `
            -Pattern $Template.Pattern `
            -Confidence ([int]($Template.Confidence ?? 85)) `
            -PatternsProximity ([int]($Template.PatternsProximity ?? 300)) `
            -Locale ($Template.Locale ?? 'en-US') `
            -PublisherName ($Template.PublisherName ?? 'CIPP')
    }
    if ([string]::IsNullOrWhiteSpace($WantXml)) {
        return [pscustomobject]@{ Name = $Name; State = 'Invalid'; Differences = @([pscustomobject]@{ Scope = 'Template'; Field = 'source'; Expected = 'Pattern or FileDataBase64'; Current = 'neither' }) }
    }

    $Sit = try {
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationType' -Compliance |
            Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    } catch { $null }

    if (-not $Sit) {
        return [pscustomobject]@{ Name = $Name; State = 'Missing'; Differences = @() }
    }
    if ($Sit.Publisher -like 'Microsoft*') {
        return [pscustomobject]@{ Name = $Name; State = 'BuiltIn'; Differences = @() }
    }

    $Pack = try {
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationTypeRulePackage' -cmdParams @{ Identity = $Sit.RulePackId } -Compliance | Select-Object -First 1
    } catch { $null }
    $HaveXml = [string]$Pack.ClassificationRuleCollectionXml

    $Want = ConvertTo-CIPPSitComparable -Xml $WantXml
    $Have = ConvertTo-CIPPSitComparable -Xml $HaveXml

    $Differences = [System.Collections.Generic.List[object]]::new()
    foreach ($EntityName in @($Want.Keys)) {
        if (-not $Have.ContainsKey($EntityName)) {
            $Differences.Add([pscustomobject]@{ Scope = "Entity '$EntityName'"; Field = '(entire entity)'; Expected = 'present'; Current = 'missing' })
            continue
        }
        $WantEntity = $Want[$EntityName]
        $HaveEntity = $Have[$EntityName]
        foreach ($Field in @('confidence', 'proximity', 'description', 'patterns')) {
            $Expected = $WantEntity[$Field]
            $Current = $HaveEntity[$Field]
            if ((ConvertTo-CIPPComparableString -Value $Expected) -ne (ConvertTo-CIPPComparableString -Value $Current)) {
                $Differences.Add([pscustomobject]@{ Scope = "Entity '$EntityName'"; Field = $Field; Expected = $Expected; Current = $Current })
            }
        }
    }

    $State = if ($Differences.Count -eq 0) { 'InSync' } else { 'Drift' }
    return [pscustomobject]@{ Name = $Name; State = $State; Differences = @($Differences) }
}
