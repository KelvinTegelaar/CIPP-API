function ConvertTo-CIPPBecHostAddress {
    <#
    .SYNOPSIS
        Strips the client port (and IPv6 brackets) from an audit-log address so one host correlates as one.
    .DESCRIPTION
        Unified-audit-log records carry the client as "203.0.113.10:51234" or "[2001:db8::1]:443", and
        the port differs on every connection. The investigation correlates activity by host, so every
        collector projects the address through this before storing it. Same normalisation the geo-IP
        batch helper applies to its keys.
    .PARAMETER Address
        The raw client address.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address)) { return $null }
    return ([regex]::Replace($Address.Trim(), '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$', '${IP}') -replace '[\[\]]', '')
}
