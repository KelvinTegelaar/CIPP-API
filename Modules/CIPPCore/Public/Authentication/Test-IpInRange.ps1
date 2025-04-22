function Test-IpInRange {
    <#
    .SYNOPSIS
    Test if an IP address is in a CIDR range
    .DESCRIPTION
    This function tests if an IP address is in a CIDR range
    .PARAMETER IPAddress
    The IP address to test
    .PARAMETER Range
    The CIDR range to test
    .EXAMPLE
    Test-IpInRange -IPAddress "1.1.1.1" -Range "1.1.1.1/24"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,
        [Parameter(Mandatory = $true)]
        [string]$Range
    )

    function ConvertIpToBigInteger {
        param([System.Net.IPAddress]$ip)
        return [System.Numerics.BigInteger]::Parse(
            [BitConverter]::ToString($ip.GetAddressBytes()).Replace('-', ''),
            [System.Globalization.NumberStyles]::HexNumber
        )
    }

    try {
        $IP = [System.Net.IPAddress]::Parse($IPAddress)
        $rangeParts = $Range -split '/'
        $networkAddr = [System.Net.IPAddress]::Parse($rangeParts[0])
        $prefix = [int]$rangeParts[1]

        if ($networkAddr.AddressFamily -ne $IP.AddressFamily) {
            return $false
        }

        $ipBig = ConvertIpToBigInteger $IP
        $netBig = ConvertIpToBigInteger $networkAddr
        $maxBits = if ($networkAddr.AddressFamily -eq 'InterNetworkV6') { 128 } else { 32 }
        $shift = $maxBits - $prefix
        $mask = [System.Numerics.BigInteger]::Pow(2, $shift) - [System.Numerics.BigInteger]::One
        $invertedMask = [System.Numerics.BigInteger]::MinusOne -bxor $mask
        $ipMasked = $ipBig -band $invertedMask
        $netMasked = $netBig -band $invertedMask

        return $ipMasked -eq $netMasked
    } catch {
        return $false
    }
}
