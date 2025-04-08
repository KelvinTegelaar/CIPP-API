
function Get-CIPPLicenseOverview {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get License Overview',
        $Headers
    )

    $Requests = @(
        @{
            id     = 'subscribedSkus'
            url    = 'subscribedSkus'
            method = 'GET'
        }
        @{
            id     = 'directorySubscriptions'
            url    = 'directory/subscriptions'
            method = 'GET'
        }
    )

    try {
        $AdminPortalLicenses = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $TenantFilter -Uri 'https://admin.microsoft.com/admin/api/tenant/accountSkus'
    } catch {
        Write-Warning 'Failed to get Admin Portal Licenses'
    }

    $Results = New-GraphBulkRequest -Requests $Requests -TenantID $TenantFilter -asapp $true
    $LicRequest = ($Results | Where-Object { $_.id -eq 'subscribedSkus' }).body.value
    $SkuIDs = ($Results | Where-Object { $_.id -eq 'directorySubscriptions' }).body.value

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
            $PrettyNameAdmin = $AdminPortalLicenses | Where-Object { $_.SkuId -eq $sku.skuId } | Select-Object -ExpandProperty Name
            $PrettyNameCSV = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
            $PrettyName = $PrettyNameAdmin ?? $PrettyNameCSV ?? $sku.skuPartNumber

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

