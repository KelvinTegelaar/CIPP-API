function Push-GetTenantDomains {
    Param($Item)
    $DomainTable = Get-CippTable -tablename 'Domains'
    $Filter = "PartitionKey eq 'TenantDomains' and TenantGUID eq '{0}'" -f $Item.TenantGUID
    $Domains = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter -Property RowKey | Select-Object RowKey, @{n = 'FunctionName'; exp = { 'DomainAnalyserDomain' } }
    return @($Domains)
}