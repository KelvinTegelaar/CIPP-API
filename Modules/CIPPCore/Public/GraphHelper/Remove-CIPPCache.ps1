function Remove-CIPPCache {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param (
        $TenantsOnly
    )
    # Remove all tenants except excluded
    $TenantsTable = Get-CippTable -tablename 'Tenants'
    $Filter = "PartitionKey eq 'Tenants' and Excluded eq false"
    $ClearIncludedTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter -Property PartitionKey, RowKey
    if ($ClearIncludedTenants) {
        Remove-AzDataTableEntity -Force @TenantsTable -Entity $ClearIncludedTenants
    }

    if ($TenantsOnly -eq 'false') {
        Write-Host 'Clearing all'
        # Remove Domain Analyser cached results
        $DomainsTable = Get-CippTable -tablename 'Domains'
        $Filter = "PartitionKey eq 'TenantDomains'"
        $ClearDomainAnalyserRows = Get-CIPPAzDataTableEntity @DomainsTable -Filter $Filter | ForEach-Object {
            $_.DomainAnalyser = ''
            $_
        }
        if ($ClearDomainAnalyserRows) {
            Update-AzDataTableEntity @DomainsTable -Entity $ClearDomainAnalyserRows
        }
        #Clear BPA
        $BPATable = Get-CippTable -tablename 'cachebpav2'
        $ClearBPARows = Get-CIPPAzDataTableEntity @BPATable
        if ($ClearBPARows) {
            Remove-AzDataTableEntity -Force @BPATable -Entity $ClearBPARows
        }
        $ENV:SetFromProfile = $null
        $Script:SkipListCache = $Null
        $Script:SkipListCacheEmpty = $Null
        $Script:IncludedTenantsCache = $Null
    }
}
