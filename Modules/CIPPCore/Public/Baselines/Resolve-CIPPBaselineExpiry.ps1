function Resolve-CIPPBaselineExpiry {
    <#
    .SYNOPSIS
        Applies the instance expiry policy to a requested expiry for an acceptance or override.
    .DESCRIPTION
        Returns the expiry in unix seconds, or $null for none. With a maximum set, a missing expiry
        becomes the default (or the maximum when there is no default), and one further away than the
        maximum is refused. One day of grace covers a date picked in a timezone ahead of UTC.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Expires)

    $Value = if ("$Expires" -match '^\d+$') { [int64]$Expires } else { $null }
    $Policy = Get-CIPPBaselineExpiryPolicy
    if ($Policy.maxDays -le 0) { return $Value }

    $Now = [datetimeoffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $Value) {
        $Days = if ($Policy.defaultDays -gt 0) { $Policy.defaultDays } else { $Policy.maxDays }
        return $Now + $Days * 86400
    }
    if ($Value -gt $Now + ($Policy.maxDays + 1) * 86400) {
        throw [System.ArgumentException]::new("The expiry can be at most $($Policy.maxDays) days away.")
    }
    $Value
}
