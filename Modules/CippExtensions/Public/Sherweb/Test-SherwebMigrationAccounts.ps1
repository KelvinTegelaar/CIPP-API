function Test-SherwebMigrationAccounts {
    [CmdletBinding()]
    param (
        $TenantFilter
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $ExtensionConfig = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json
    $Config = $ExtensionConfig.Sherweb
    #First get a list of all subscribed skus for this tenant, that are in the transfer window.
    $Licenses = (Get-CIPPLicenseOverview -TenantFilter $TenantFilter) | Where-Object { $null -ne $_.terminfo -and $_.terminfo.TransferWindow -le 7 }

    #now check if this exact count of licenses is available at Sherweb, if not, we need to migrate them.
    $SherwebLicenses = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
    $LicencesToMigrate = foreach ($License in $Licenses) {
        foreach ($termInfo in $License.terminfo) {
            $matchedSherweb = $SherwebLicenses | Where-Object { $_.quantity -eq $termInfo.TotalLicenses -and $_.commitmentTerm.termEndDate -eq $termInfo.NextLifecycle }
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

    switch -wildcard ($config.migrationMethods) {
        '*notify*' {
            $Subject = "Sherweb Migration: $($TenantFilter) - $($LicencesToMigrate.Count) licenses to migrate"
            $HTMLContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'html' -InputObject 'sherwebmig'
            $JSONContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'json' -InputObject 'sherwebmig'
            Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
            Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $standardsTenant -APIName 'Alerts'
            Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $Tenant -APIName 'Alerts'
        }
        '*buy*' {
            try {
                $PotentialLicenses = Get-SherwebCatalog -TenantFilter $TenantFilter | Where-Object { $_.microsoftSkuId -in $LicencesToMigrate.SkuId -and $_.sku -like "*$($Config.migrateToLicense)" }
                if (!$PotentialLicenses) {
                    throw 'cannot buy new license: no matching license found in catalog'
                } else {
                    $PotentialLicenses | ForEach-Object {
                        Set-SherwebSubscription -TenantFilter $TenantFilter -SKU $PotentialLicenses.sku -Quantity $LicencesToMigrate.TotalLicensesAtUnknownCSP
                    }
                }
            } catch {
                $Subject = "Sherweb Migration: $($TenantFilter) - Failed to buy licenses."
                $HTMLContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'html' -InputObject 'sherwebmigBuyFail'
                $JSONContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'json' -InputObject 'sherwebmigBuyFail'
                Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $standardsTenant -APIName 'Alerts'
                Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $Tenant -APIName 'Alerts'
            }

        }
        '*Cancel' {
            try {
                $tenantid = (Get-Tenants -TenantFilter $TenantFilter).customerId
                $Pax8Config = $ExtensionConfig.Pax8
                $Pax8ClientId = $Pax8Config.clientId
                $Pax8ClientSecret = Get-ExtensionAPIKey -Extension 'Pax8'
                $paxBody = @{
                    client_id     = $Pax8ClientId
                    client_secret = $Pax8ClientSecret
                    audience      = 'https://api.pax8.com'
                    grant_type    = 'client_credentials'
                }
                $Token = Invoke-RestMethod -Uri 'https://api.pax8.com/v1/token' -Method POST -Headers $headers -ContentType 'application/json' -Body $paxBody
                $headers = @{ Authorization = "Bearer $($Token.access_token)" }
                $cancelSubList = Invoke-RestMethod -Uri "https://api.pax8.com/v1/subscriptions?page=0&size=10&status=Active&companyId=$($tenantid)" -Method GET -Headers $headers | Where-Object -Property productId -In $LicencesToMigrate.SkuId
                $cancelSubList | ForEach-Object {
                    $response = Invoke-RestMethod -Uri "https://api.pax8.com/v1/subscriptions/$($_.subscriptionId)" -Method DELETE -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json)
                }

            } catch {
                $Subject = 'Sherweb Migration: Pax Migration failed'
                $HTMLContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'html' -InputObject 'sherwebmigfailpax'
                $JSONContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'json' -InputObject 'sherwebmigfailpax'
                Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $standardsTenant -APIName 'Alerts'
                Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $Tenant -APIName 'Alerts'
            }
        }

    }
}
