# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"

$RawGraphRequest = Get-Tenants | ForEach-Object -Parallel { 
    $domainName = $_.defaultDomainName
    Import-Module '.\GraphHelper.psm1'
    Import-Module '.\Modules\AzBobbyTables'

    try {
        $Licrequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $_.defaultDomainName -ErrorAction Stop
        [PSCustomObject]@{
            Tenant   = $domainName
            Licenses = $Licrequest
        } 
    }
    catch {
        [PSCustomObject]@{
            Tenant   = $domainName
            Licenses = @{ 
                skuid         = "Could not connect to client"
                skuPartNumber = "Could not connect to client"
                consumedUnits = 0 
                prepaidUnits  = { Enabled = 0 }
            }
        } 
    }
}
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$ConvertTable = Import-Csv Conversiontable.csv
$Table = Get-CIPPTable -TableName cachelicenses
$LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
$ExcludedSkuList = Get-AzDataTableEntity @LicenseTable

$GraphRequest = foreach ($singlereq in $RawGraphRequest) {
    $skuid = $singlereq.Licenses
    foreach ($sku in $skuid) {
        if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
        $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
        if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
        @{
            Tenant         = "$($singlereq.Tenant)"
            License        = "$PrettyName"
            CountUsed      = "$($sku.consumedUnits)"
            CountAvailable = "$($sku.prepaidUnits.enabled - $sku.consumedUnits)"
            TotalLicenses  = "$($sku.prepaidUnits.enabled)"
            skuId          = "$($sku.skuid)"
            skuPartNumber  = "$PrettyName"
            availableUnits = "$($sku.prepaidUnits.enabled - $sku.consumedUnits)"
            PartitionKey   = 'License'
            RowKey         = "$($singlereq.Tenant) - $($sku.skuid)"
        }      
    }
}

Write-Host "$($GraphRequest.RowKey) - $($GraphRequest.tenant)"
Add-AzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
