function ConvertFrom-CIPPGSAForwardingRule {
    <#
    .SYNOPSIS
        Flattens Internet Access forwarding rules into one entry per destination.
    .DESCRIPTION
        Each entry is { destination, ports, protocols }: the destination as typed (an FQDN, an IP
        address, a subnet, or a range as begin-end), its ports joined with commas, and the protocols
        it is matched on. A destination listed in a TCP rule and a UDP rule with the same ports is one
        entry with protocols 'tcp,udp'. Entries are sorted, so two rule sets compare as equal lists.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Rules)

    $Entries = [ordered]@{}
    foreach ($Rule in @($Rules)) {
        if (-not $Rule) { continue }
        $Ports = (@($Rule.ports).Where({ $_ }) | Sort-Object) -join ','
        foreach ($Destination in @($Rule.destinations)) {
            $Value = if ($Destination.beginAddress) { "$($Destination.beginAddress)-$($Destination.endAddress)" } else { "$($Destination.value)" }
            if (-not $Value) { continue }
            $Key = "$($Value.ToLowerInvariant())|$Ports"
            if (-not $Entries.Contains($Key)) { $Entries[$Key] = [pscustomobject]@{ destination = $Value; ports = $Ports; protocols = [System.Collections.Generic.SortedSet[string]]::new() } }
            $null = $Entries[$Key].protocols.Add("$($Rule.protocol)".ToLowerInvariant())
        }
    }
    @($Entries.Values | Sort-Object destination, ports).ForEach({ [pscustomobject]@{ destination = $_.destination; ports = $_.ports; protocols = @($_.protocols) -join ',' } })
}
