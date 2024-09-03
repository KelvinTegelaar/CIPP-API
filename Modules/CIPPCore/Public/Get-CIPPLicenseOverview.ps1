
function Get-CIPPLicenseOverview {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get License Overview',
        $ExecutingUser
    )


    $LicRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
    $SkuIDs = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directory/subscriptions' -tenantid $TenantFilter

    $RawGraphRequest = [PSCustomObject]@{
        Tenant   = $TenantFilter
        Licenses = $LicRequest
    }
    Set-Location (Get-Item $PSScriptRoot).FullName
    $ConvertTable = Import-Csv ConversionTable.csv
    $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
    $ExcludedSkuList = Get-CIPPAzDataTableEntity @LicenseTable
    $GraphRequest = foreach ($singlereq in $RawGraphRequest) {
        $skuid = $singlereq.Licenses
        foreach ($sku in $skuid) {
            if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
            $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
            if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }

            # Initialize $Term with the default value
            $TermInfo = foreach ($Subscription in $sku.subscriptionIds) {
                $SubInfo = $SkuIDs | Where-Object { $_.id -eq $Subscription }
                $diff = $SubInfo.nextLifecycleDateTime - $SubInfo.createdDateTime
                $Term = 'Term unknown or non-NCE license'
                if ($diff.Days -ge 360 -and $diff.Days -le 1089) {
                    $Term = 'Yearly'
                } elseif ($diff.Days -ge 1090 -and $diff.Days -le 1100) {
                    $Term = '3 Year'
                } elseif ($diff.Days -ge 25 -and $diff.Days -le 35) {
                    $Term = 'Monthly'
                }
                $TimeUntilRenew = ($subinfo.nextLifecycleDateTime - (Get-Date)).days
                [PSCustomObject]@{
                    Status            = $SubInfo.status
                    Term              = $Term
                    TotalLicenses     = $SubInfo.totalLicenses
                    DaysUntilRenew    = $TimeUntilRenew
                    NextLifecycle     = $SubInfo.nextLifecycleDateTime
                    IsTrial           = $SubInfo.isTrial
                    SubscriptionId    = $subinfo.id
                    CSPSubscriptionId = $SubInfo.commerceSubscriptionId
                    OCPSubscriptionId = $SubInfo.ocpSubscriptionId
                }
            }
            [pscustomobject]@{
                Tenant         = [string]$singlereq.Tenant
                License        = [string]$PrettyName
                CountUsed      = [string]"$($sku.consumedUnits)"
                CountAvailable = [string]$sku.prepaidUnits.enabled - $sku.consumedUnits
                TotalLicenses  = [string]"$($sku.prepaidUnits.enabled)"
                skuId          = [string]$sku.skuId
                skuPartNumber  = [string]$PrettyName
                availableUnits = [string]$sku.prepaidUnits.enabled - $sku.consumedUnits
                TermInfo       = [string]($TermInfo | ConvertTo-Json -Depth 10 -Compress)
                'PartitionKey' = 'License'
                'RowKey'       = "$($singlereq.Tenant) - $($sku.skuid)"
            }
        }
    }
    return $GraphRequest
}

