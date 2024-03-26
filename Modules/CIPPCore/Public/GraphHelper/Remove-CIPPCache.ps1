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
    $ClearIncludedTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
    Remove-AzDataTableEntity @TenantsTable -Entity $ClearIncludedTenants
    if ($tenantsonly -eq 'false') {
        Write-Host 'Clearing all'
        # Remove Domain Analyser cached results
        $DomainsTable = Get-CippTable -tablename 'Domains'
        $Filter = "PartitionKey eq 'TenantDomains'"
        $ClearDomainAnalyserRows = Get-CIPPAzDataTableEntity @DomainsTable -Filter $Filter | ForEach-Object {
            $_.DomainAnalyser = ''
            $_
        }
        Update-AzDataTableEntity @DomainsTable -Entity $ClearDomainAnalyserRows
        #Clear BPA
        $BPATable = Get-CippTable -tablename 'cachebpa'
        $ClearBPARows = Get-CIPPAzDataTableEntity @BPATable
        Remove-AzDataTableEntity @BPATable -Entity $ClearBPARows
        $ENV:SetFromProfile = $null
        $Script:SkipListCache = $Null
        $Script:SkipListCacheEmpty = $Null
        $Script:IncludedTenantsCache = $Null
    }
}
