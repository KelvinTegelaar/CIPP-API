function Test-SherwebMigrationAccounts {
    [CmdletBinding()]
    param (
        $TenantFilter
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Sherweb
    #First get a list of all subscribed skus for this tenant, that are in the transfer window.
    $Licenses = (Get-CIPPLicenseOverview -TenantFilter $TenantFilter) | ForEach-Object { $_.terminfo = ($_.terminfo | ConvertFrom-Json -ErrorAction SilentlyContinue) ; $_ } | Where-Object { $_.terminfo -ne $null -and $_.terminfo.TransferWindow -LE 78 }

    #now check if this exact count of licenses is available at Sherweb, if not, we need to migrate them.
    $SherwebLicenses = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
    $LicencesToMigrate = foreach ($License in $Licenses) {
        foreach ($termInfo in $License.terminfo) {
            $matchedSherweb = $SherwebLicenses | Where-Object { $_.quantity -eq 3 -and $_.commitmentTerm.termEndDate -eq $termInfo.NextLifecycle }
            if (-not $matchedSherweb) {
                [PSCustomObject]@{
                    LicenseName                  = ($Licenses | Where-Object { $_.skuId -eq $License.skuId }).license
                    SkuId                        = $License.skuId
                    SubscriptionId               = $termInfo.SubscriptionId
                    Term                         = $termInfo.Term
                    NextLifecycle                = $termInfo.NextLifecycle
                    TotalLicensesAtUnknownCSP    = $termInfo.TotalLicenses
                    TotalLicensesAvailableInM365 = ($Licenses | Where-Object { $_.skuId -eq $License.skuId }).TotalLicenses
                }

            }
        }
    }

    switch ($config.migrationMethods) {
        notifyOnly {
            #Create HTML report for this tenant. Send to webhook/notifications/etc
        }
        buyAndNotify {
            #Create HTML report for this tenant. Send to webhook/notifications/etc
            #Buy the licenses at Sherweb using the matching CSV.
        }
        buyAndCancel {
            #Create HTML report for this tenant. Send to webhook/notifications/etc
            #Buy the licenses at Sherweb using the matching CSV.
            #Cancel the licenses in old vendor.
        }

    }
}
