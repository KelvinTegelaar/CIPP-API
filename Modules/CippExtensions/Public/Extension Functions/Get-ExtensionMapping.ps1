function Get-ExtensionMapping {
    param(
        $Extension
    )

    $Table = Get-CIPPTable -TableName CippMapping
    $Mapping = @{}
    Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Extension)Mapping'" | ForEach-Object {
        $Mapping[$_.RowKey] = @{
            label = "$($_.IntegrationName)"
            value = "$($_.IntegrationId)"
        }
    }
    return [PSCustomObject]$Mapping
}