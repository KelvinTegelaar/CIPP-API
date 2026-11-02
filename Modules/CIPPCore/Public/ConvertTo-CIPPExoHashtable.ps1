function ConvertTo-CIPPExoHashtable {
    <#
    .SYNOPSIS
        Convert a value into the hashtable shape the EXO AdminApi accepts for PswsHashtable parameters.
    .DESCRIPTION
        Hashtable-typed cmdlet parameters (e.g. Set-Label -AdvancedSettings, New-LabelPolicy -Settings)
        sent over the AdminApi REST endpoint deserialize server-side as Newtonsoft JObjects, which the
        parameter binder cannot convert to PswsHashtable. Tagging the object with
        '@odata.type' = '#Exchange.GenericHashTable' makes the binder accept it - the same convention
        used elsewhere in CIPP for MultiValuedProperty add/remove hashtables.

        Accepts a dictionary, a PSCustomObject (deserialized JSON object), or an array of key/value
        pairs in either the {Key, Value} object shape or the [key, value] pair shape used by label
        policy Settings in template JSON.
    .PARAMETER InputObject
        The value to convert.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject
    )

    $Result = @{ '@odata.type' = '#Exchange.GenericHashTable' }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($Key in @($InputObject.Keys)) {
            if ($Key -ne '@odata.type') { $Result[$Key] = $InputObject[$Key] }
        }
    } elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        foreach ($Entry in $InputObject) {
            if ($null -eq $Entry) { continue }
            if ($Entry -isnot [string] -and $Entry.PSObject.Properties['Key']) {
                $Result[$Entry.Key] = $Entry.Value
            } elseif ($Entry -is [System.Collections.IList] -and $Entry.Count -ge 2) {
                $Result["$($Entry[0])"] = $Entry[1]
            }
        }
    } else {
        foreach ($Prop in $InputObject.PSObject.Properties) {
            if ($Prop.Name -ne '@odata.type') { $Result[$Prop.Name] = $Prop.Value }
        }
    }

    return $Result
}
