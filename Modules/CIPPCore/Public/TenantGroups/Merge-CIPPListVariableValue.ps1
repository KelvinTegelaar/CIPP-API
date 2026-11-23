function Merge-CIPPListVariableValue {
    <#
    .SYNOPSIS
        The value a custom variable takes over the one it inherits
    .DESCRIPTION
        A list or collection variable set to join inherited values adds its entries to an inherited list or
        collection, skipping duplicates. Anything else replaces the inherited value, as variables always have.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $InheritedValue,
        [string]$InheritedType,
        $Value,
        [string]$VariableType,
        $JoinInherited
    )

    $ListTypes = @('list', 'collection')
    if ($JoinInherited -ne $true -or $null -eq $InheritedValue -or $VariableType -notin $ListTypes -or $InheritedType -notin $ListTypes) {
        return $Value
    }
    $Items = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Json in @($InheritedValue, $Value)) {
        try {
            $Parsed = ConvertFrom-Json -InputObject ([string]$Json) -Depth 100 -NoEnumerate -ErrorAction Stop
        } catch {
            continue
        }
        foreach ($Item in @($Parsed)) {
            if ($Seen.Add((ConvertTo-Json -InputObject $Item -Depth 100 -Compress))) { $Items.Add($Item) }
        }
    }
    return (ConvertTo-Json -InputObject $Items.ToArray() -Depth 100 -Compress)
}
