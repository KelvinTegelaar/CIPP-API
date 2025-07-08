function Get-ExtensionMapping {
    param(
        $Extension
    )

    $Table = Get-CIPPTable -TableName CippMapping
    return Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Extension)Mapping'"
}
