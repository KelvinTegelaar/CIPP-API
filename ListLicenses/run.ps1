using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$RawGraphRequest = if ($TenantFilter -ne "AllTenants") {
    $LicRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscribedSkus" -tenantid $TenantFilter
    [PSCustomObject]@{
        Tenant   = $TenantFilter
        Licenses = $LicRequest
    }
}
else {
    Get-Tenants | ForEach-Object { 
        try {
            $Licrequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscribedSkus" -tenantid $_.defaultDomainName -ErrorAction Stop
            [PSCustomObject]@{
                Tenant   = $_.defaultDomainName
                Licenses = $Licrequest
            } 
        }
        catch {
        }
    }
}
$ConvertTable = Import-Csv Conversiontable.csv

$GraphRequest = $RawGraphRequest | ForEach-Object {
    $skuid = $_.Licenses
    foreach ($sku in $skuid) {
        $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
        if (!$PrettyName) { $PrettyName = $skuid.skuPartNumber }
        [PSCustomObject]@{
            Tenant         = $_.Tenant
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

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })