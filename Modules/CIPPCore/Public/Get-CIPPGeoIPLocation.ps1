function Get-CIPPGeoIPLocation {
    [CmdletBinding()]
    param (
        $IP
    )
    if ($IP -like '*:*') { $IP = $IP.split(':')[0] }
    $CTX = new-azdatatablecontext -TableName geoipdb -ConnectionString 'TableEndpoint=https://cyberdraingeoipdb.table.core.windows.net/;SharedAccessSignature=sv=2022-11-02&ss=t&srt=o&sp=rl&se=2025-08-08T21:05:23Z&st=2023-08-08T13:05:23Z&spr=https&sig=89Bmk2Un89xqNzZPLkryFnLRCjHs9rCWGUJjhvf5mso%3D'
    $GeoTable = @{ Context = $CTX }

    $IPAsint = 0
    $IP.Split(".") | ForEach-Object {
        $IPAddressByte = 0
        [int]::TryParse($_, [ref] $IPAddressByte) | Out-Null
        $IPAsint = ([long]($IPAsint -shl 8)) -bor [byte]$_
    }

    $location = (Get-AzDataTableEntity @GeoTable -Filter "PartitionKey eq 'GeoIP' and RowKey le '$IPAsint' and ipTo ge '$IPAsint'") | Select-Object -Last 1

    return $location
}
