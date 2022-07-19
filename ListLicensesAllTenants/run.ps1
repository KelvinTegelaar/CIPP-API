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


$RawGraphRequest = Get-Tenants | ForEach-Object -parallel { 
    Import-Module '.\GraphHelper.psm1'
    try {
        $Licrequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscribedSkus" -tenantid $_.defaultDomainName -ErrorAction Stop
        [PSCustomObject]@{
            Tenant   = $_.defaultDomainName
            Licenses = $Licrequest
        } 
    }
    catch {
        [PSCustomObject]@{
            Tenant   = $_.defaultDomainName
            Licenses = "Could not retrieve licenses"
        } 
    }
}

$ConvertTable = Import-Csv Conversiontable.csv

$GraphRequest = foreach ($singlereq in $RawGraphRequest) {
    $skuid = $singlereq.Licenses
    foreach ($sku in $skuid) {
        $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
        if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
        @{
            Tenant         = $singlereq.Tenant
            License        = $PrettyName
            CountUsed      = "$($sku.consumedUnits)"
            CountAvailable = $sku.prepaidUnits.enabled - $sku.consumedUnits
            TotalLicenses  = "$($sku.prepaidUnits.enabled)"
            skuId          = $sku.skuId
            skuPartNumber  = $PrettyName
            availableUnits = $sku.prepaidUnits.enabled - $sku.consumedUnits
        }      
    }
}
$Table = Get-CIPPTable -TableName cachelicenses

foreach ($Request in $GraphRequest) {
    $TableRow = @{
        table        = $Table
        partitionKey = 'License'
        rowKey       = "$($Request.tenant)-$($Request.skuId)"
        property     = $Request
    }
    Add-AzTableRow @TableRow -UpdateExisting | Out-Null
}