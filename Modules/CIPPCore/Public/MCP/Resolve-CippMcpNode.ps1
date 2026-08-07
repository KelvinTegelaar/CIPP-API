function Resolve-CippMcpNode {
    <#
    .SYNOPSIS
        Deep-resolves a parsed OpenAPI node (hashtable/array/scalar), inlining any $ref.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Node, $Spec, [int]$Depth = 0, [string[]]$Seen = @())

    if ($null -eq $Node) { return $null }
    if ($Depth -gt 15) { return @{ type = 'object' } }
    if ($Node -is [string] -or $Node -is [valuetype]) { return $Node }

    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains('$ref')) {
            $Ref = [string]$Node['$ref']
            if ($Seen -contains $Ref) { return [ordered]@{ type = 'object'; description = 'recursive reference omitted' } }
            $Target = Resolve-CippMcpRef -Ref $Ref -Spec $Spec
            return Resolve-CippMcpNode -Node $Target -Spec $Spec -Depth ($Depth + 1) -Seen ($Seen + $Ref)
        }
        $Out = [ordered]@{}
        foreach ($Entry in $Node.GetEnumerator()) {
            if ($Entry.Key -eq '$ref') { continue }
            $Out[[string]$Entry.Key] = Resolve-CippMcpNode -Node $Entry.Value -Spec $Spec -Depth ($Depth + 1) -Seen $Seen
        }
        return $Out
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        $Resolved = @($Node | ForEach-Object { Resolve-CippMcpNode -Node $_ -Spec $Spec -Depth ($Depth + 1) -Seen $Seen })
        return , $Resolved
    }

    return $Node
}
