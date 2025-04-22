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
    "Removed $($ClearIncludedTenants.Count) tenants"

    if ($TenantsOnly -eq $false) {
        'Clearing all cached table data'
        $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage
        $Tables = Get-AzDataTable -Context $Context
        foreach ($Table in $Tables) {
            if ($Table -match '^cache') {
                "Removing cache table $Table"
                $TableContext = Get-CIPPTable -TableName $Table
                Remove-AzDataTable @TableContext
            }
        }

        'Clearing domain analyser results'
        # Remove Domain Analyser cached results
        $DomainsTable = Get-CippTable -tablename 'Domains'
        $Filter = "PartitionKey eq 'TenantDomains'"
        $ClearDomainAnalyserRows = Get-CIPPAzDataTableEntity @DomainsTable -Filter $Filter | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name DomainAnalyser -Value '' -Force
            $_
        }
        if ($ClearDomainAnalyserRows) {
            Update-AzDataTableEntity -Force @DomainsTable -Entity $ClearDomainAnalyserRows
        }

        $env:SetFromProfile = $null
        $Script:SkipListCache = $Null
        $Script:SkipListCacheEmpty = $Null
        $Script:IncludedTenantsCache = $Null
    }
    'Cache cleanup complete'
}
