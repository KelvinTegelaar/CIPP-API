
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
        @{
            id      = 'licensedUsers'
            url     = "users?`$select=id,displayName,userPrincipalName,assignedLicenses&`$filter=assignedLicenses/`$count ne 0&`$count=true"
            method  = 'GET'
            headers = @{
                'ConsistencyLevel' = 'eventual'
            }
        }
        @{
            id      = 'licensedGroups'
            url     = "groups?`$select=id,displayName,assignedLicenses,mailEnabled,securityEnabled,groupTypes,onPremisesSyncEnabled&`$filter=assignedLicenses/`$count ne 0&`$count=true"
            method  = 'GET'
            headers = @{
                'ConsistencyLevel' = 'eventual'
            }
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

    $AllLicensedUsers = @(($Results | Where-Object { $_.id -eq 'licensedUsers' }).body.value)
    $UsersBySku = @{}
    foreach ($User in $AllLicensedUsers) {
        if (-not $User.assignedLicenses) { continue } # Skip users with no assigned licenses. Should not happens as the filter is applied, but just in case
        $UserInfo = [PSCustomObject]@{
            displayName       = [string]$User.displayName
            userPrincipalName = [string]$User.userPrincipalName
            id                = [string]$User.id
        }

        foreach ($AssignedLicense in $User.assignedLicenses) {
            $LicenseSkuId = ([string]$AssignedLicense.skuId).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($LicenseSkuId)) { continue } # Skip if SKU ID is null or whitespace. Should not happen but just in case
            if (-not $UsersBySku.ContainsKey($LicenseSkuId)) {
                $UsersBySku[$LicenseSkuId] = [System.Collections.Generic.List[object]]::new()
            }
            $UsersBySku[$LicenseSkuId].Add($UserInfo)
        }

    }

    $AllLicensedGroups = @(($Results | Where-Object { $_.id -eq 'licensedGroups' }).body.value)
    $GroupsBySku = @{}
    foreach ($Group in $AllLicensedGroups) {
        if (-not $Group.assignedLicenses) { continue }
        $GroupInfo = [PSCustomObject]@{
            displayName           = [string]$Group.displayName
            calculatedGroupType   = if ($Group.groupTypes -contains 'Unified') { 'Microsoft 365' }
            elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'Mail-Enabled Security' }
            elseif (-not $Group.mailEnabled -and $Group.securityEnabled) { 'Security' }
            elseif (([string]::isNullOrEmpty($Group.groupTypes)) -and ($Group.mailEnabled) -and (-not $Group.securityEnabled)) { 'Distribution List' }
            id                    = [string]$Group.id
            onPremisesSyncEnabled = [bool]$Group.onPremisesSyncEnabled

        }
        foreach ($AssignedLicense in $Group.assignedLicenses) {
            $LicenseSkuId = ([string]$AssignedLicense.skuId).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($LicenseSkuId)) { continue }
            if (-not $GroupsBySku.ContainsKey($LicenseSkuId)) {
                $GroupsBySku[$LicenseSkuId] = [System.Collections.Generic.List[object]]::new()
            }
            $GroupsBySku[$LicenseSkuId].Add($GroupInfo)
        }
    }
    $GraphRequest = foreach ($singleReq in $RawGraphRequest) {
        $skuId = $singleReq.Licenses
        foreach ($sku in $skuId) {
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
            $SkuKey = ([string]$sku.skuId).ToLowerInvariant()
            [pscustomobject]@{
                Tenant         = [string]$singleReq.Tenant
                License        = [string]$PrettyName
                CountUsed      = [string]"$($sku.consumedUnits)"
                CountAvailable = [string]$sku.prepaidUnits.enabled - $sku.consumedUnits
                TotalLicenses  = [string]"$($sku.prepaidUnits.enabled)"
                skuId          = [string]$sku.skuId
                skuPartNumber  = [string]$PrettyName
                availableUnits = [string]$sku.prepaidUnits.enabled - $sku.consumedUnits
                TermInfo       = [string]($TermInfo | ConvertTo-Json -Depth 10 -Compress)
                AssignedUsers  = ($UsersBySku.ContainsKey($SkuKey) ? @(($UsersBySku[$SkuKey])) : $null)
                AssignedGroups = ($GroupsBySku.ContainsKey($SkuKey) ? @(($GroupsBySku[$SkuKey])) : $null)
                'PartitionKey' = 'License'
                'RowKey'       = "$($singleReq.Tenant) - $($sku.skuid)"
            }
        }
    }
    return $GraphRequest
}
