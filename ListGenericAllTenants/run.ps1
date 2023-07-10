# Input bindings are passed in via param block.
param([string]$QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"
$TableURLName = ($QueueItem.tolower().split('?').Split('/') | Select-Object -First 1).toString()
$QueueKey = (Get-CippQueue | Where-Object -Property Name -EQ $TableURLName | Select-Object -Last 1).RowKey
Update-CippQueueEntry -RowKey $QueueKey -Status 'Started'
$Table = Get-CIPPTable -TableName "cache$TableURLName"
$fullUrl = "https://graph.microsoft.com/beta/$QueueItem"
Get-AzDataTableEntity @Table | Remove-AzDataTableEntity @table

$RawGraphRequest = Get-Tenants | ForEach-Object -Parallel { 
    $domainName = $_.defaultDomainName
    Import-Module '.\GraphHelper.psm1'
    try {
        Write-Host $using:fullUrl
        New-GraphGetRequest -uri $using:fullUrl -tenantid $_.defaultDomainName -ComplexFilter -ErrorAction Stop | Select-Object *, @{l = 'Tenant'; e = { $domainName } }, @{l = 'CippStatus'; e = { 'Good' } }
    }
    catch {
        [PSCustomObject]@{
            Tenant     = $domainName
            CippStatus = "Could not connect to tenant. $($_.Exception.message)"
        }
    } 
}

Update-CippQueueEntry -RowKey $QueueKey -Status 'Processing'
foreach ($Request in $RawGraphRequest) {
    $Json = ConvertTo-Json -Compress -InputObject $request
    $GraphRequest = [PSCustomObject]@{
        Tenant       = [string]$Request.tenant
        RowKey       = [string](New-Guid)
        PartitionKey = [string]$URL
        Data         = [string]$Json

    }
    Add-AzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
}


Update-CippQueueEntry -RowKey $QueueKey -Status 'Completed'