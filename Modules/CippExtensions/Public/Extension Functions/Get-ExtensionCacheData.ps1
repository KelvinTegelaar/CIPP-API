function Get-ExtensionCacheData {
    param(
        $TenantFilter
    )

    $Table = Get-CIPPTable -TableName CacheExtensionSync
    $CacheData = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter'"

    $Return = @{}
    foreach ($Data in $CacheData) {
        try {
            $Return[$Data.RowKey] = $Data.Data | ConvertFrom-Json -ErrorAction SilentlyContinue
        } catch {
            Write-Information "Failed to convert cache data for $($Data.RowKey) to JSON"
        }
    }
    return [PSCustomObject]$Return
}
