function ConvertTo-CippMcpHashtable {
    <#
    .SYNOPSIS
        Normalizes a JSON-RPC deserialized object (IDictionary or PSCustomObject) into a hashtable.
    .DESCRIPTION
        MCP arguments and Functions-worker headers arrive either as dictionaries or as
        PSCustomObjects depending on how the JSON body was deserialized. PSObject.Properties on a
        dictionary yields .NET members (Count, Keys, ...) rather than entries, so both shapes need
        explicit handling. Scalars return an empty hashtable.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($InputObject)

    $Out = @{}
    if ($null -eq $InputObject -or $InputObject -is [string] -or $InputObject -is [valuetype]) {
        return $Out
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($Entry in $InputObject.GetEnumerator()) {
            $Out[[string]$Entry.Key] = $Entry.Value
        }
    } else {
        foreach ($Prop in $InputObject.PSObject.Properties) {
            $Out[$Prop.Name] = $Prop.Value
        }
    }
    return $Out
}
