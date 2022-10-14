using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$RawGraphRequest = if ($TenantFilter -ne 'AllTenants') {
    $LicRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
    [PSCustomObject]@{
        Tenant   = $TenantFilter
        Licenses = $LicRequest
    }
}
else {
    $Table = Get-CIPPTable -TableName cachelicenses
    $Rows = Get-AzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
    if (!$Rows) {
        Push-OutputBinding -Name Msg -Value (Get-Date).ToString()
        [PSCustomObject]@{
            Tenant   = 'Loading data for all tenants. Please check back in 1 minute'
            Licenses = 'Loading data for all tenants. Please check back in 1 minute'
        }
    }         
    else {
        $GraphRequest = $Rows
    }
}
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$ConvertTable = Import-Csv Conversiontable.csv
$LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
$ExcludedSkuList = Get-AzDataTableEntity @LicenseTable
if (!$GraphRequest) {
    $GraphRequest = foreach ($singlereq in $RawGraphRequest) {
        $skuid = $singlereq.Licenses
        foreach ($sku in $skuid) {
            if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
            $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
            if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
            [PSCustomObject]@{
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
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    }) -Clobber