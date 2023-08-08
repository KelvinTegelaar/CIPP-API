# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"

$RawGraphRequest = Get-Tenants | ForEach-Object -Parallel { 
    $domainName = $_.defaultDomainName
    Import-Module '.\GraphHelper.psm1'
    Import-Module '.\Modules\AzBobbyTables'
    Import-Module '.\Modules\CIPPCore'
    try {
        Get-CIPPLicenseOverview -TenantFilter $domainName
    }
    catch {
       [pscustomobject]@{
            Tenant         = [string]$domainName
            License        = "Could not connect to client"
            'PartitionKey' = 'License'
            'RowKey'       = "$($domainName) - Could not connect to client"
        } 
    }
}

$Table = Get-CIPPTable -TableName cachelicenses
Add-AzDataTableEntity @Table -Entity $RawGraphRequest -Force | Out-Null