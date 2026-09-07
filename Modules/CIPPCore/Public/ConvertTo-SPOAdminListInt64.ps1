function ConvertTo-SPOAdminListInt64 {
    <#
    .SYNOPSIS
        Parse RenderAdminListData numeric fields (comma-separated strings) to int64.

    .DESCRIPTION
        SPO.Tenant/RenderAdminListData returns counts and byte sizes as strings like
        "1,073,741,824". Returns $null for empty or unparseable values.

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

    $Clean = ([string]$Raw).Replace(',', '').Trim()
    if ($Clean -eq '') { return $null }

    $Parsed = [int64]0
    if ([int64]::TryParse($Clean, [ref]$Parsed)) {
        return $Parsed
    }
    return $null
}
