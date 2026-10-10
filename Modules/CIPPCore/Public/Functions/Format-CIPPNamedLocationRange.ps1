function Format-CIPPNamedLocationRange {
    <#
    .SYNOPSIS
        Expands an IP named location's ranges into one Graph range object per CIDR
    .DESCRIPTION
        A list variable used for IP ranges arrives as plain CIDR strings, or as one range whose
        cidrAddress is an array. Graph accepts only one range object per CIDR.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Location)

    if (-not $Location -or -not $Location.PSObject.Properties['ipRanges']) { return }
    $Location.ipRanges = @(foreach ($Range in @($Location.ipRanges)) {
            if ($Range -isnot [string] -and @($Range.cidrAddress).Count -le 1) { $Range; continue }
            $Cidrs = if ($Range -is [string]) { $Range } else { $Range.cidrAddress }
            foreach ($Cidr in @($Cidrs)) {
                if ([string]::IsNullOrWhiteSpace($Cidr)) { continue }
                [pscustomobject]@{
                    '@odata.type' = if ($Cidr.Contains(':')) { '#microsoft.graph.iPv6CidrRange' } else { '#microsoft.graph.iPv4CidrRange' }
                    cidrAddress   = $Cidr
                }
            }
        })
}
