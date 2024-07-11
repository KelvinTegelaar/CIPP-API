function Get-ExtensionCacheData {
    param(
        $TenantFilter
    )

    $Table = Get-CIPPTable -TableName CacheExtensionSync
    $CacheData = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter'"

    $Return = @{}
    foreach ($Data in $CacheData) {
        $Return[$Data.RowKey] = $Data.Data | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    return [PSCustomObject]$Return
}
