function ConvertTo-CIPPCoverImageIdList {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Normalizes coverImageIds from an array or JSON string to a string[].
    .DESCRIPTION
        Always returns a real string array (possibly empty). A single-element
        result must not unwrap to a scalar string — callers index with [0]
        and expect a full id, not the first character of a GUID.
    #>
    [CmdletBinding()]
    param($Value)

    $Ids = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $Value -or $Value -eq '') {
        return , [string[]]@()
    }

    if ($Value -is [string]) {
        try {
            $Parsed = $Value | ConvertFrom-Json
            if ($null -eq $Parsed) {
                return , [string[]]@()
            }
            if ($Parsed -is [string]) {
                if ($Parsed) { $Ids.Add("$Parsed") | Out-Null }
                return , [string[]]@($Ids.ToArray())
            }
            if ($Parsed -is [System.Collections.IEnumerable]) {
                foreach ($Item in @($Parsed)) {
                    if ($null -ne $Item -and "$Item" -ne '') {
                        $Ids.Add("$Item") | Out-Null
                    }
                }
                return , [string[]]@($Ids.ToArray())
            }
            if ("$Parsed") {
                $Ids.Add("$Parsed") | Out-Null
            }
            return , [string[]]@($Ids.ToArray())
        } catch {
            return , [string[]]@()
        }
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($Item in @($Value)) {
            if ($null -ne $Item -and "$Item" -ne '') {
                $Ids.Add("$Item") | Out-Null
            }
        }
        return , [string[]]@($Ids.ToArray())
    }

    return , [string[]]@()
}
