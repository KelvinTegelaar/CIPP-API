function Get-CIPPSitSinglePackXml {
    <#
    .SYNOPSIS
        Reduce a (possibly multi-SIT) rule pack XML to a standalone pack containing just one SIT.
    .DESCRIPTION
        Custom regex SITs each get their own pack, but document-fingerprint SITs all share the one fixed
        "Document Fingerprint Rule Package". To template just one SIT, this keeps the target entity and the
        transitive closure of everything it references (by idRef / linkedProcessorIdRef), and removes every
        other entity, its detection elements, and its Resource - then assigns a fresh RulePack id so the
        result deploys as a new custom pack.

        Subtractive (rather than rebuilding) so the original structure is preserved exactly, including the
        fingerprint shape where the Affinity entity is nested inside a <Version minEngineVersion> wrapper.
        Works for regex (Entity -> Pattern -> Regex/Keyword) and fingerprint (Affinity -> Evidence ->
        Fingerprint -> AdvancedFingerprint) alike. Namespace-agnostic.
    .PARAMETER PackXml
        The full rule pack XML (e.g. from Get-DlpSensitiveInformationTypeRulePackage).
    .PARAMETER EntityId
        The SIT entity id (the SIT's Id). If blank, resolved from EntityName via the Resource.
    .PARAMETER EntityName
        The SIT name, used to resolve the entity id when EntityId is blank.
    .OUTPUTS
        A single-SIT rule pack XML string (utf-16 declared).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackXml,
        [string]$EntityId,
        [string]$EntityName
    )

    [xml]$doc = $PackXml

    # Resolve the entity id from the SIT name if needed (Resource.Name -> Resource.idRef).
    if ([string]::IsNullOrWhiteSpace($EntityId) -and $EntityName) {
        foreach ($res in $doc.SelectNodes("//*[local-name()='Resource']")) {
            $nm = $res.SelectSingleNode("*[local-name()='Name']")
            if ($nm -and ([string]$nm.InnerText).Trim() -eq $EntityName) { $EntityId = [string]$res.idRef; break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($EntityId)) { throw 'Could not resolve the SIT entity id.' }

    # Map every element that carries an id (anywhere - entities can be nested in a Version wrapper).
    $byId = @{}
    foreach ($el in $doc.SelectNodes("//*[@id]")) { $byId[[string]$el.id] = $el }
    if (-not $byId.ContainsKey($EntityId)) { throw "Entity '$EntityId' not found in the rule package." }

    # Transitive closure of ids the target entity needs.
    $keep = New-Object 'System.Collections.Generic.HashSet[string]'
    [void]$keep.Add($EntityId)
    $stack = New-Object System.Collections.Stack
    $stack.Push($byId[$EntityId])
    while ($stack.Count -gt 0) {
        $el = $stack.Pop()
        $walk = New-Object System.Collections.Stack
        $walk.Push($el)
        while ($walk.Count -gt 0) {
            $n = $walk.Pop()
            foreach ($a in @($n.Attributes)) {
                if ($a.Name -in @('idRef', 'linkedProcessorIdRef')) {
                    $rid = [string]$a.Value
                    if ($byId.ContainsKey($rid) -and -not $keep.Contains($rid)) {
                        [void]$keep.Add($rid)
                        $stack.Push($byId[$rid])
                    }
                }
            }
            foreach ($ch in $n.ChildNodes) { if ($ch.NodeType -eq 'Element') { $walk.Push($ch) } }
        }
    }

    # Remove other entities, the detection elements they (and not the target) own, and other Resources.
    $toRemove = New-Object System.Collections.ArrayList
    foreach ($e in $doc.SelectNodes("//*[local-name()='Entity' or local-name()='Affinity']")) {
        if ([string]$e.id -ne $EntityId) { [void]$toRemove.Add($e) }
    }
    foreach ($e in $doc.SelectNodes("//*[local-name()='Regex' or local-name()='Keyword' or local-name()='Fingerprint' or local-name()='AdvancedFingerprint']")) {
        if (-not $keep.Contains([string]$e.id)) { [void]$toRemove.Add($e) }
    }
    foreach ($r in $doc.SelectNodes("//*[local-name()='Resource']")) {
        if ([string]$r.idRef -ne $EntityId) { [void]$toRemove.Add($r) }
    }
    foreach ($node in $toRemove) { [void]$node.ParentNode.RemoveChild($node) }

    # Fresh RulePack id so this deploys as a new custom pack (not the fixed managed pack id).
    $rulePack = $doc.SelectSingleNode("//*[local-name()='RulePack']")
    if ($rulePack -and $rulePack.Attributes['id']) { $rulePack.id = (New-Guid).Guid }

    return '<?xml version="1.0" encoding="utf-16"?>' + $doc.DocumentElement.OuterXml
}
