function ConvertTo-CIPPGSAForwardingRule {
    <#
    .SYNOPSIS
        Builds Internet Access forwarding rules from destination lines.
    .DESCRIPTION
        Destinations are FQDNs (wildcards allowed), IPv4 addresses, subnets (CIDR) or ranges written
        begin-end. They are grouped into one rule per destination type and protocol, which is how the
        portal stores them. Ports are a comma-separated list of ports or ranges ('443', '8000-8100');
        blank means all ports. Throws an ArgumentException for a destination or port that is not valid.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string[]]$Destinations,
        [ValidateSet('bypass', 'forward')][string]$Action,
        [string]$Ports,
        [string[]]$Protocols = @('tcp', 'udp')
    )

    $Ipv4 = '(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)'
    $PortList = @("$Ports" -split ',').ForEach({ $_.Trim() }).Where({ $_ })
    if ($PortList.Count -eq 0) { $PortList = @('0-65535') }
    foreach ($Port in $PortList) {
        if ($Port -notmatch '^\d{1,5}(-\d{1,5})?$') { throw [System.ArgumentException]::new("'$Port' is not a port or port range") }
    }

    $ByType = [ordered]@{}
    foreach ($Raw in @($Destinations)) {
        $Value = "$Raw".Trim()
        if (-not $Value) { continue }
        $Destination = switch -Regex ($Value) {
            "^$Ipv4/(?:3[0-2]|[12]?\d)$" { @{ ruleType = 'ipSubnet'; body = [ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.ipSubnet'; value = $Value } }; break }
            "^($Ipv4)\s*-\s*($Ipv4)$" { @{ ruleType = 'ipRange'; body = [ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.ipRange'; beginAddress = $Matches[1]; endAddress = $Matches[2] } }; break }
            "^$Ipv4$" { @{ ruleType = 'ipAddress'; body = [ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.ipAddress'; value = $Value } }; break }
            '^(\*\.)?([a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$|^\*$' { @{ ruleType = 'fqdn'; body = [ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.fqdn'; value = $Value.ToLowerInvariant() } }; break }
            default { throw [System.ArgumentException]::new("'$Value' is not an FQDN, IPv4 address, subnet or range") }
        }
        if (-not $ByType.Contains($Destination.ruleType)) { $ByType[$Destination.ruleType] = [System.Collections.Generic.List[object]]::new() }
        $ByType[$Destination.ruleType].Add($Destination.body)
    }

    foreach ($Type in $ByType.Keys) {
        foreach ($Protocol in $Protocols) {
            [ordered]@{
                '@odata.type' = '#microsoft.graph.networkaccess.internetAccessForwardingRule'
                name          = "CIPP $Action $Type $($Protocol.ToUpperInvariant())"
                ruleType      = $Type
                action        = $Action
                protocol      = $Protocol
                ports         = @($PortList)
                destinations  = @($ByType[$Type])
            }
        }
    }
}
