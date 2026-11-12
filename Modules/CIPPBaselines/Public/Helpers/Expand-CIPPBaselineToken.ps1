function Expand-CIPPBaselineToken {
    <#
    .SYNOPSIS
        Substitutes %name% tokens in the string values of a parsed template.
    .DESCRIPTION
        Works on the parsed object, never on serialized JSON, so a value can only ever become a
        value - it cannot add, remove or override keys. A string that is exactly "%name%" takes
        the value with its type; a token inside a longer string takes the value's string form.
        Returns new containers; the template is not modified.
          -Values     object whose properties are the token values, applied in property order.
          -WholeOnly  names that may only fill an exact "%name%" string, never an embedded token.
          -Omit       tokens whose property is dropped when the property value is exactly the token.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Template,
        $Values,
        [string[]]$WholeOnly = @(),
        [string[]]$Omit = @()
    )

    $Tokens = [System.Collections.Generic.List[object]]::new()
    foreach ($Property in @($Values.PSObject.Properties)) {
        $Tokens.Add([PSCustomObject]@{
                Token    = '%{0}%' -f $Property.Name
                Value    = $Property.Value
                Embedded = $WholeOnly -notcontains $Property.Name
            })
    }

    $Walk = {
        param($Node, $Substitute)
        if ($Node -is [string]) {
            if (-not $Substitute -or -not $Node.Contains('%')) { return $Node }
            foreach ($Entry in $Tokens) {
                # The value is copied without substitution, so one value never expands another.
                if ($Node -ceq $Entry.Token) { return , (& $Walk $Entry.Value $false) }
            }
            foreach ($Entry in $Tokens) {
                if ($Entry.Embedded) { $Node = $Node.Replace($Entry.Token, "$($Entry.Value)") }
            }
            return $Node
        }
        if ($Node -is [System.Collections.IDictionary]) { $Node = [PSCustomObject]$Node }
        if ($Node -is [System.Management.Automation.PSCustomObject]) {
            $Copy = [PSCustomObject]@{}
            foreach ($Property in $Node.PSObject.Properties) {
                if ($Substitute -and $Property.Value -is [string] -and $Omit -ccontains $Property.Value) { continue }
                $Copy.PSObject.Properties.Add([psnoteproperty]::new($Property.Name, (& $Walk $Property.Value $Substitute)))
            }
            return $Copy
        }
        if ($Node -is [System.Collections.IList]) {
            $List = [System.Collections.Generic.List[object]]::new()
            foreach ($Element in $Node) { $List.Add((& $Walk $Element $Substitute)) }
            return , $List.ToArray()
        }
        $Node
    }

    , (& $Walk $Template $true)
}
