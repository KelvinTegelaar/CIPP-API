function Get-TenantProperties {
    param (
        [string]$customerId
    )

    $tableName = 'TenantProperties'
    $Table = Get-CIPPTable -TableName $tableName

    $SafeCustomerId = ConvertTo-CIPPODataFilterValue -Value $customerId -Type String
    $Query = "PartitionKey eq '$SafeCustomerId'"
    $tenantProperties = @(Get-CIPPAzDataTableEntity @Table -Filter $Query)

    if ($tenantProperties.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($customerId)) {
        $Tenant = Get-Tenants -TenantFilter $customerId -IncludeErrors | Select-Object -First 1
        $ResolvedCustomerId = $Tenant.customerId

        if (-not [string]::IsNullOrWhiteSpace($ResolvedCustomerId) -and $ResolvedCustomerId -ne $customerId) {
            $SafeResolvedCustomerId = ConvertTo-CIPPODataFilterValue -Value $ResolvedCustomerId -Type String
            $ResolvedQuery = "PartitionKey eq '$SafeResolvedCustomerId'"
            $tenantProperties = @(Get-CIPPAzDataTableEntity @Table -Filter $ResolvedQuery)
        }
    }

    $properties = @{}
    foreach ($property in $tenantProperties) {
        $properties[$property.RowKey] = $property.Value
    }

    return $properties
}
