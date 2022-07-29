# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"
Write-Host "Queue item expiration time: $($TriggerMetadata.ExpirationTime)"
Write-Host "Queue item insertion time: $($TriggerMetadata.InsertionTime)"
Write-Host "Queue item next visible time: $($TriggerMetadata.NextVisibleTime)"
Write-Host "ID: $($TriggerMetadata.Id)"
Write-Host "Pop receipt: $($TriggerMetadata.PopReceipt)"
Write-Host "Dequeue count: $($TriggerMetadata.DequeueCount)"


$RawGraphRequest = Get-Tenants | ForEach-Object -Parallel { 
    Import-Module '.\GraphHelper.psm1'
    try {
        $Licrequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $_.defaultDomainName -ErrorAction Stop
        [PSCustomObject]@{
            Tenant   = $_.defaultDomainName
            Licenses = $Licrequest
        } 
    }
    catch {
        [PSCustomObject]@{
            Tenant   = $_.defaultDomainName
            Licenses = 'Could not retrieve licenses'
        } 
    }
}

$ConvertTable = Import-Csv Conversiontable.csv
$Table = Get-CIPPTable -TableName cachelicenses


$GraphRequest = foreach ($singlereq in $RawGraphRequest) {
    $skuid = $singlereq.Licenses
    foreach ($sku in $skuid) {
        if (!$sku.skuId) { $SkuId = "Could not connect" } else { $skuId = $sku.skuid }
        $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
        if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
        @{
            Tenant         = "$($singlereq.Tenant)"
            License        = "$PrettyName"
            CountUsed      = "$($sku.consumedUnits)"
            CountAvailable = "$($sku.prepaidUnits.enabled - $sku.consumedUnits)"
            TotalLicenses  = "$($sku.prepaidUnits.enabled)"
            skuId          = "$SkuId"
            skuPartNumber  = "$PrettyName"
            availableUnits = "$($sku.prepaidUnits.enabled - $sku.consumedUnits)"
            PartitionKey   = 'License'
            RowKey         = "$($singlereq.tenant)-$SkuId"
        }      
    }
}

Write-Host "$($GraphRequest.RowKey) - $($GraphRequest.tenant)"
Add-AzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
