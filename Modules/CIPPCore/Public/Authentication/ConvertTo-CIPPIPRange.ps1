function ConvertTo-CIPPIPRange {
    <#
    .SYNOPSIS
        Validates and normalises an IP address or CIDR range.
    .DESCRIPTION
        Accepts "203.0.113.10", "203.0.113.0/24", "2001:db8::1" or "2001:db8::/48" (surrounding
        whitespace and IPv6 brackets are ignored) and returns the canonical text form: the address
        as .NET prints it, plus "/prefix" when a prefix narrower than a single host is given. Throws
        on anything that is not an IP address or a valid prefix length for its family.
    .PARAMETER Value
        The address or range.
    .EXAMPLE
        ConvertTo-CIPPIPRange -Value ' 203.0.113.0/24 '   # 203.0.113.0/24
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $Text = $Value.Trim() -replace '[\[\]]', ''
    if (-not $Text) { throw 'An IP address or range is required' }
    $Parts = $Text -split '/'
    if ($Parts.Count -gt 2) { throw "'$Value' is not a valid IP address or CIDR range" }
    $Address = $null
    if (-not [System.Net.IPAddress]::TryParse($Parts[0], [ref]$Address) -or $Parts[0] -notmatch '[.:]') {
        throw "'$Value' is not a valid IP address or CIDR range"
    }
    $MaxBits = if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) { 128 } else { 32 }
    if ($Parts.Count -eq 1) { return $Address.ToString() }
    $Prefix = 0
    if (-not [int]::TryParse($Parts[1], [ref]$Prefix) -or $Prefix -lt 0 -or $Prefix -gt $MaxBits) {
        throw "'$Value' has an invalid prefix length (0-$MaxBits)"
    }
    if ($Prefix -eq $MaxBits) { return $Address.ToString() }
    return "$($Address.ToString())/$Prefix"
}
