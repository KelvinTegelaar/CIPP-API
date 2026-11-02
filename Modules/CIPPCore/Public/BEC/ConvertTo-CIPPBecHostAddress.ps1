function ConvertTo-CIPPBecHostAddress {
    <#
    .SYNOPSIS
        Reduces an audit-log or sign-in address to one canonical host form so one host correlates as one.
    .DESCRIPTION
        Unified-audit-log records carry the client as "203.0.113.10:51234" or "[2001:db8::1]:443", and
        the port differs on every connection; IPv6 arrives in upper or lower case, compressed or not, and
        an IPv4 client can show up IPv4-mapped ("::ffff:203.0.113.10"). The investigation correlates
        activity by host, so every collector projects the address through this before storing it: the
        port and brackets go, IPv6 is written the one standard way (RFC 5952, lower case) and a mapped
        IPv4 address becomes plain IPv4. Text that is not an address is returned trimmed, unchanged.
    .PARAMETER Address
        The raw client address.
    .PARAMETER Network
        Return the IPv6 /64 the address belongs to ("2001:db8:1:2::/64") instead of the host. One
        device rotates through many addresses inside its /64 (privacy addresses), and everyone on one
        LAN shares it, so the /64 is what an IPv4 address means for "the user's network". IPv4
        addresses are returned as the host.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Address, [switch]$Network)

    if ([string]::IsNullOrWhiteSpace($Address)) { return $null }
    $Text = $Address.Trim()
    $Endpoint = $null
    if (-not [System.Net.IPEndPoint]::TryParse($Text, [ref]$Endpoint)) { return $Text }
    $IP = $Endpoint.Address
    if ($IP.IsIPv4MappedToIPv6) { $IP = $IP.MapToIPv4() }
    elseif ($IP.AddressFamily -eq 'InterNetwork' -and $Text -notmatch '^\d{1,3}(\.\d{1,3}){3}(:\d+)?$') {
        # .NET also reads "12345" or "1.2" as IPv4; only a dotted quad is one here
        return $Text
    }
    if ($IP.AddressFamily -ne 'InterNetworkV6') { return $IP.ToString() }
    $Bytes = $IP.GetAddressBytes()
    if ($Network) { [Array]::Clear($Bytes, 8, 8) }
    $Canonical = [System.Net.IPAddress]::new($Bytes).ToString()
    if ($Network) { "$Canonical/64" } else { $Canonical }
}
