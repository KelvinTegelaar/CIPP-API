function Assert-CIPPWebhookDestination {
    <#
    .SYNOPSIS
    Refuse a webhook URL that is not https or that points at this host or a private network
    .DESCRIPTION
    Throws unless -Uri is an absolute https URL whose host resolves only to public addresses.
    Loopback, private, link-local, carrier-grade NAT and unspecified addresses are refused.
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Uri
    )

    $Parsed = $null
    if (-not [uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$Parsed) -or $Parsed.Scheme -ne 'https' -or $Parsed.UserInfo) {
        throw 'Webhook URL must be an https URL without embedded credentials.'
    }

    $Address = $null
    $Addresses = if ([System.Net.IPAddress]::TryParse($Parsed.IdnHost.Trim('[', ']'), [ref]$Address)) {
        @($Address)
    } else {
        # ponytail: resolved here and again by the HTTP client, so a DNS answer that changes in between is not caught. Pin the connection to the checked address if that matters.
        try { @([System.Net.Dns]::GetHostAddresses($Parsed.IdnHost)) } catch { @() }
    }
    if ($Addresses.Count -eq 0) {
        throw "Webhook URL host '$($Parsed.Host)' could not be resolved."
    }

    foreach ($Ip in $Addresses) {
        if ($Ip.IsIPv4MappedToIPv6) { $Ip = $Ip.MapToIPv4() }
        $Bytes = $Ip.GetAddressBytes()
        $Blocked = if ($Ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            $Bytes[0] -in 0, 10, 127 -or
            ($Bytes[0] -eq 100 -and $Bytes[1] -ge 64 -and $Bytes[1] -le 127) -or
            ($Bytes[0] -eq 169 -and $Bytes[1] -eq 254) -or
            ($Bytes[0] -eq 172 -and $Bytes[1] -ge 16 -and $Bytes[1] -le 31) -or
            ($Bytes[0] -eq 192 -and $Bytes[1] -eq 168)
        } else {
            [System.Net.IPAddress]::IsLoopback($Ip) -or $Ip.Equals([System.Net.IPAddress]::IPv6Any) -or
            $Ip.IsIPv6LinkLocal -or $Ip.IsIPv6SiteLocal -or ($Bytes[0] -band 0xFE) -eq 0xFC
        }
        if ($Blocked) {
            throw "Webhook URL host '$($Parsed.Host)' points at a local or private address, which is not allowed."
        }
    }
}
