
function Get-CIPPLicenseOverview {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = "Get License Overview",
        $ExecutingUser
    )

   
    $LicRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
    $LicOverviewRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directory/subscriptions' -tenantid $TenantFilter | Where-Object -Property nextLifecycleDateTime -GT (Get-Date)  | Select-Object *,
    @{Name = 'consumedUnits'; Expression = { ($LicRequest | Where-Object -Property skuid -EQ $_.skuId).consumedUnits } },
    @{Name = 'prepaidUnits'; Expression = { ($LicRequest | Where-Object -Property skuid -EQ $_.skuId).prepaidUnits } }

    $RawGraphRequest = [PSCustomObject]@{
        Tenant   = $TenantFilter
        Licenses = $LicOverviewRequest
    }
    Set-Location (Get-Item $PSScriptRoot).FullName
    $ConvertTable = Import-Csv Conversiontable.csv
    $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
    $ExcludedSkuList = Get-AzDataTableEntity @LicenseTable
    $GraphRequest = foreach ($singlereq in $RawGraphRequest) {
        $skuid = $singlereq.Licenses
        foreach ($sku in $skuid) {
            if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
            $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
            if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
            $diff = $sku.nextLifecycleDateTime - $sku.createdDateTime
            # Initialize $Term with the default value
            $Term = "Term unknown or non-NCE license"
            if ($diff.Days -ge 360 -and $diff.Days -le 1089) {
                $Term = "Yearly"
            }
            elseif ($diff.Days -ge 1090 -and $diff.Days -le 1100) {
                $Term = "3 Year"
            }
            elseif ($diff.Days -ge 25 -and $diff.Days -le 35) {
                $Term = "Monthly"
            }
            $TimeUntilRenew = $sku.nextLifecycleDateTime - (Get-Date)
            [pscustomobject]@{
                Tenant         = [string]$singlereq.Tenant
                License        = [string]$PrettyName
                CountUsed      = [string]"$($sku.consumedUnits)"
                CountAvailable = [string]$sku.prepaidUnits.enabled - $sku.consumedUnits
                TotalLicenses  = [string]"$($sku.TotalLicenses)"
                skuId          = [string]$sku.skuId
                skuPartNumber  = [string]$PrettyName
                availableUnits = [string]$sku.prepaidUnits.enabled - $sku.consumedUnits
                EstTerm        = [string]$Term
                TimeUntilRenew = [string]"$($TimeUntilRenew.Days)"
                Trial          = [bool]$sku.isTrial
                dateCreated    = [string]$sku.createdDateTime
                dateExpires    = [string]$sku.nextLifecycleDateTime
                'PartitionKey' = 'License'
                'RowKey'       = "$($singlereq.Tenant) - $($sku.skuid)"
            }      
        }
    }
    return $GraphRequest
}

