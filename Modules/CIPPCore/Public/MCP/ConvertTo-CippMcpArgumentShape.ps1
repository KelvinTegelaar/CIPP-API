function ConvertTo-CippMcpArgumentShape {
    <#
    .SYNOPSIS
        Coerces MCP tool arguments to match the tool's input schema, wrapping a bare scalar into
        the { value } object shape a CIPP endpoint actually reads.
    .DESCRIPTION
        CIPP autocomplete/select fields are read as $Request.Body.<field>.value, so the generated
        spec documents them as LabelValue objects ({ "value": "..." }). Nothing on the dispatch
        path validated arguments against that schema, so an MCP caller that sent a bare string for
        such a field made .value resolve to $null at the endpoint. For a field that scopes a query
        (a user or tenant selector, say) that silently dropped the scope and returned an UNSCOPED
        200 rather than erroring.

        This walks the top-level schema properties and, where a property is a LabelValue-shaped
        object (an object schema carrying a 'value' property) or an array of them, wraps a bare
        scalar the caller sent into @{ value = <scalar> } (or an array of those). $ref is already
        inlined in the catalog's inputSchema, so the LabelValue component arrives here as a plain
        object schema. Anything already the right shape, and any field the schema does not
        describe, is returned exactly as received.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Arguments,
        $InputSchema
    )

    if (-not $Arguments -or $Arguments.Count -eq 0) { return $Arguments }
    if ($InputSchema -isnot [System.Collections.IDictionary]) { return $Arguments }
    $Properties = $InputSchema['properties']
    if ($Properties -isnot [System.Collections.IDictionary]) { return $Arguments }

    # An object schema is CIPP's autocomplete/select shape when it carries a 'value' property -
    # the field the backend reads as $Field.value.
    $IsLabelValue = {
        param($Schema)
        if ($Schema -isnot [System.Collections.IDictionary]) { return $false }
        $Props = $Schema['properties']
        if ($Props -isnot [System.Collections.IDictionary]) { return $false }
        return [bool](@($Props.Keys) | Where-Object { "$_".ToLowerInvariant() -eq 'value' })
    }

    # A JSON scalar: string, number or boolean. Objects (hashtable / PSCustomObject) and arrays
    # are already structured and are left untouched.
    $IsScalar = { param($Value) $null -ne $Value -and ($Value -is [string] -or $Value -is [valuetype]) }

    foreach ($Name in @($Arguments.Keys)) {
        if (-not $Properties.Contains($Name)) { continue }
        $Schema = $Properties[$Name]
        if ($Schema -isnot [System.Collections.IDictionary]) { continue }
        $Value = $Arguments[$Name]

        if (& $IsLabelValue $Schema) {
            # Object-shaped LabelValue: wrap a bare scalar so $Field.value resolves.
            if (& $IsScalar $Value) {
                $Arguments[$Name] = @{ value = $Value }
            }
        } elseif ($Schema['type'] -eq 'array' -and (& $IsLabelValue $Schema['items'])) {
            # Array of LabelValue: wrap each bare scalar element, and a bare scalar into a
            # single-element array, leaving elements the caller already shaped as objects.
            if (& $IsScalar $Value) {
                $Arguments[$Name] = @(@{ value = $Value })
            } elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                $Arguments[$Name] = @(foreach ($Item in $Value) {
                        if (& $IsScalar $Item) { @{ value = $Item } } else { $Item }
                    })
            }
        }
    }

    return $Arguments
}
