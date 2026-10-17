function ConvertTo-SPOAdminListInt64 {
    <#
    .SYNOPSIS
        Parse RenderAdminListData numeric fields to int64, including localized grouping separators
        and integral decimal representations (e.g. 68478349774.0000).

    .DESCRIPTION
        SPO.Tenant/RenderAdminListData returns counts and byte sizes as localized strings,
        e.g. "68 478 349 774" or "68478349774.0000". Reject fractional quantities,
        nonnumeric values and Int64 overflow instead of guessing.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Raw
    )

    if ($null -eq $Raw -or $Raw -eq '') { return $null }
    if ($Raw -is [int64]) { return $Raw }
    if ($Raw -is [int] -or $Raw -is [long]) { return [int64]$Raw }

    # Admin UI formats grouping with commas, regular spaces, NBSP or narrow NBSP.
    # Keep the numeric check strict so localized text and fractional byte counts fail closed.
    $Clean = (([string]$Raw).Trim() -replace '[,\s]', '')
    if ($Clean -notmatch '^[+-]?[0-9]+(?:\.0+)?$') { return $null }
    $Clean = $Clean -replace '\.0+$', ''

    $Parsed = [int64]0
    if ([int64]::TryParse($Clean, [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed)) {
        return $Parsed
    }
    return $null
}
