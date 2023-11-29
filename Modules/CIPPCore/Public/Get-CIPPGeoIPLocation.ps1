function Get-CIPPGeoIPLocation {
    [CmdletBinding()]
    param (
        [string]$IP
    )

    if ($IP -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$') {
        $IP = $IP -replace ':\d+$', '' # Remove the port number if present
    }

    $partitionKey = "GeoIP"
    $IPAsint = [System.Numerics.BigInteger]::Zero
    $ipAddress = [System.Net.IPAddress]::Parse($IP)
    if ($ipAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        $partitionKey = "GeoIPv6"
        $bytes = $ipAddress.GetAddressBytes()
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            $IPAsint = $IPAsint -shl 8 -bor $bytes[$i]
        }
    }
    else {
        $IP.Split(".") | ForEach-Object {
            $IPAddressByte = 0
            [int]::TryParse($_, [ref] $IPAddressByte) | Out-Null
            $IPAsint = ([long]($IPAsint -shl 8)) -bor [byte]$_
        }
    }

    $CTX = New-AzDataTableContext -TableName geoipdb -ConnectionString 'TableEndpoint=https://cyberdraingeoipdb.table.core.windows.net/;SharedAccessSignature=sv=2022-11-02&ss=t&srt=o&sp=rl&se=2025-08-08T21:05:23Z&st=2023-08-08T13:05:23Z&spr=https&sig=89Bmk2Un89xqNzZPLkryFnLRCjHs9rCWGUJjhvf5mso%3D'
    $GeoTable = @{ Context = $CTX }
    $location = (Get-CIPPAzDataTableEntity @GeoTable -Filter "PartitionKey eq '$partitionKey' and RowKey le '$IPAsint' and ipTo ge '$IPAsint'") | Select-Object -Last 1

    return $location
}
