function Get-TenantProperties {
    param (
        [string]$customerId
    )

    $tableName = 'TenantProperties'
    $query = "PartitionKey eq '$customerId'"
    $Table = Get-CIPPTable -TableName $tableName
    $tenantProperties = Get-CIPPAzDataTableEntity @Table -Filter $query

    $properties = @{}
    foreach ($property in $tenantProperties) {
        $properties[$property.RowKey] = $property.Value
    }

    return $properties
}
