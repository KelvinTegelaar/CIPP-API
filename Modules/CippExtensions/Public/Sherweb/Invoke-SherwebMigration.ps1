function Invoke-SherwebMigration {
    [CmdletBinding()]
    param (
        $TenantFilter
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $ExtensionConfig = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json
    $Config = $ExtensionConfig.Sherweb

    if ($Config.Enabled -ne $true) {
        Write-Information "Sherweb extension is disabled, skipping migration check for $TenantFilter"
        return
    }

    # Get licenses within the transfer window (renewing within 7 days)
    $Licenses = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | Where-Object {
        $null -ne $_.TermInfo -and ($_.TermInfo | Where-Object { $_.DaysUntilRenew -le 7 -and $_.DaysUntilRenew -ge 0 })
    }

    if (-not $Licenses) { return }

    # Check if the exact count of licenses is available at Sherweb, if not, we need to migrate them.
    $SherwebLicenses = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
    $LicencesToMigrate = foreach ($License in $Licenses) {
        foreach ($Term in $License.TermInfo) {
            if ($Term.DaysUntilRenew -gt 7 -or $Term.DaysUntilRenew -lt 0) { continue }
            $matchedSherweb = $SherwebLicenses | Where-Object { $_.quantity -eq $Term.TotalLicenses -and $_.commitmentTerm.termEndDate -eq $Term.NextLifecycle }
            if (-not $matchedSherweb) {
                [PSCustomObject]@{
                    LicenseName                  = $License.License
                    SkuId                        = $License.skuId
                    SubscriptionId               = $Term.SubscriptionId
                    Term                         = $Term.Term
                    NextLifecycle                = $Term.NextLifecycle
                    DaysUntilRenew               = $Term.DaysUntilRenew
                    TotalLicensesAtUnknownCSP    = $Term.TotalLicenses
                    TotalLicensesAvailableInM365 = $License.TotalLicenses
                }
            }
        }
    }

    if (-not $LicencesToMigrate) { return }

    switch -wildcard ($Config.migrationMethods) {
        '*notify*' {
            $Subject = "Sherweb Migration: $($TenantFilter) - $($LicencesToMigrate.Count) licenses to migrate"
            $HTMLContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'html' -InputObject 'sherwebmig'
            $JSONContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'json' -InputObject 'sherwebmig'
            Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $TenantFilter -APIName 'Alerts'
            Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $TenantFilter -APIName 'Alerts'
            Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $TenantFilter -APIName 'Alerts'
        }
        '*buy*' {
            try {
                foreach ($MigLicense in $LicencesToMigrate) {
                    $PotentialLicense = Get-SherwebCatalog -TenantFilter $TenantFilter | Where-Object { $_.microsoftSkuId -eq $MigLicense.SkuId -and $_.sku -like "*$($Config.migrateToLicense)" } | Select-Object -First 1
                    if (-not $PotentialLicense) {
                        throw "Cannot buy new license: no matching license found in catalog for SKU $($MigLicense.SkuId)"
                    }
                    Set-SherwebSubscription -TenantFilter $TenantFilter -SKU $PotentialLicense.sku -Quantity $MigLicense.TotalLicensesAtUnknownCSP
                }
            } catch {
                $Subject = "Sherweb Migration: $($TenantFilter) - Failed to buy licenses."
                $HTMLContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'html' -InputObject 'sherwebmigBuyFail'
                $JSONContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'json' -InputObject 'sherwebmigBuyFail'
                Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $TenantFilter -APIName 'Alerts'
                Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $TenantFilter -APIName 'Alerts'
                Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $TenantFilter -APIName 'Alerts'
            }
        }
        '*cancel*' {
            try {
                $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
                $Pax8Config = $ExtensionConfig.Pax8
                $Pax8ClientId = $Pax8Config.clientId
                $Pax8ClientSecret = Get-ExtensionAPIKey -Extension 'Pax8'
                $paxBody = @{
                    client_id     = $Pax8ClientId
                    client_secret = $Pax8ClientSecret
                    audience      = 'https://api.pax8.com'
                    grant_type    = 'client_credentials'
                }
                $Token = Invoke-RestMethod -Uri 'https://api.pax8.com/v1/token' -Method POST -Body $paxBody -ContentType 'application/x-www-form-urlencoded'
                $Pax8Headers = @{ Authorization = "Bearer $($Token.access_token)" }
                $cancelSubList = (Invoke-RestMethod -Uri "https://api.pax8.com/v1/subscriptions?page=0&size=100&status=Active&companyId=$($TenantId)" -Method GET -Headers $Pax8Headers).content | Where-Object { $_.productId -in $LicencesToMigrate.SkuId }
                foreach ($Sub in $cancelSubList) {
                    #Cancelbody can be NULL, or a date in the format of 2000-10-31T01:30:00.000-05:00. This used to just be $null
                    $cancelBody = @{ cancellationDate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }
                    $null = Invoke-RestMethod -Uri "https://api.pax8.com/v1/subscriptions/$($Sub.id)" -Method DELETE -Headers $Pax8Headers -ContentType 'application/json' -Body ($cancelBody | ConvertTo-Json)
                }
            } catch {
                $Subject = "Sherweb Migration: $($TenantFilter) - Pax8 cancellation failed."
                $HTMLContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'html' -InputObject 'sherwebmigfailcancel'
                $JSONContent = New-CIPPAlertTemplate -Data $LicencesToMigrate -Format 'json' -InputObject 'sherwebmigfailcancel'
                Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $TenantFilter -APIName 'Alerts'
                Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $TenantFilter -APIName 'Alerts'
                Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $TenantFilter -APIName 'Alerts'
            }
        }
    }
}
