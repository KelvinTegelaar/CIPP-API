function ConvertTo-StringList {
    <#
    .SYNOPSIS
        Turns encoded list data into something you can foreach over.

    .DESCRIPTION
        String input: if it is JSON (object or array), it is converted first; otherwise comma/semicolon/newline
        splitting applies. Other shapes: wrapper objects, or an existing array/list. After conversion, the return
        value is always foreach-able (empty collection is @()). Arrays and IList instances are returned
        as-is — they are already foreach-able without conversion.
        This exists because front end multi-value input is annoying to deal with.

    .PARAMETER InputObject
        Encoded list (string/JSON), wrapper object, or an existing array/list.

    .PARAMETER PropertyNames
        On hashtables/PSCustomObjects, property names to read in order.

    .OUTPUTS
        Always an enumerable suitable for: foreach ($item in (ConvertTo-StringList ...)) { }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias('Input', 'Value')]
        [AllowNull()]
        $InputObject,

        [string[]]$PropertyNames = @('Items', 'Value')
    )

    # Output must be foreach-able; $null input yields empty collection.
    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [string]) {
        $s = $InputObject.Trim()
        if (-not $s) {
            return @()
        }
        if ($s.StartsWith('[') -or $s.StartsWith('{')) {
            try {
                $parsed = $s | ConvertFrom-Json -ErrorAction Stop
                return ConvertTo-StringList -InputObject $parsed -PropertyNames $PropertyNames
            } catch {
            }
        }
        return @(
            $s -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        )
    }

    if ($InputObject -is [Array]) {
        return $InputObject
    }
    if ($InputObject -is [System.Collections.IList] -and $InputObject -isnot [string]) {
        return $InputObject
    }

    if ($InputObject -is [hashtable]) {
        if ($InputObject.Count -eq 0) {
            return @()
        }
        foreach ($name in $PropertyNames) {
            if ($InputObject.ContainsKey($name)) {
                return ConvertTo-StringList -InputObject $InputObject[$name] -PropertyNames $PropertyNames
            }
        }
        foreach ($p in $InputObject.GetEnumerator() | Sort-Object { $_.Key }) {
            $v = $p.Value
            if ($null -eq $v) { continue }
            if ($v -is [string] -or ($v -is [System.Collections.IEnumerable] -and $v -isnot [hashtable] -and $v -isnot [pscustomobject])) {
                return ConvertTo-StringList -InputObject $v -PropertyNames @()
            }
        }
        $single = "$InputObject".Trim()
        if ($single) {
            return , @($single)
        }
        return @()
    }

    if ($InputObject -is [pscustomobject]) {
        foreach ($name in $PropertyNames) {
            if ($InputObject.PSObject.Properties.Name -contains $name) {
                return ConvertTo-StringList -InputObject $InputObject.$name -PropertyNames $PropertyNames
            }
        }
        foreach ($p in $InputObject.PSObject.Properties) {
            $v = $p.Value
            if ($null -eq $v) { continue }
            if ($v -is [string] -or ($v -is [System.Collections.IEnumerable] -and $v -isnot [hashtable] -and $v -isnot [pscustomobject])) {
                return ConvertTo-StringList -InputObject $v -PropertyNames @()
            }
        }
        $single = "$InputObject".Trim()
        if ($single) {
            return , @($single)
        }
        return @()
    }

    $t = "$InputObject".Trim()
    if ($t) {
        return , @($t)
    }
    return @()
}
