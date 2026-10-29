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
                $PatternMatches = @($p.SelectNodes(".//*[@idRef]") | ForEach-Object {
                        $ref = [string]$_.idRef
                        if ($regexMap.ContainsKey($ref)) { "regex:$($regexMap[$ref])" }
                        elseif ($keywordMap.ContainsKey($ref)) { "keyword:$($keywordMap[$ref])" }
                        else { "ref:$ref" }
                    }) | Sort-Object
                [ordered]@{ level = [string]$p.confidenceLevel; matches = @($PatternMatches) }
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
