function New-GradientServiceSyncRun {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ()

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Gradient
    $APIName = 'GradientSync'
    $Tenants = Get-Tenants
    #creating accounts in Gradient
    try {
        $GradientToken = Get-GradientToken -Configuration $Configuration
        $ExistingAccounts = (Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/accounts' -Method GET -Headers $GradientToken)
        $NewAccounts = $Tenants | Where-Object defaultDomainName -NotIn $ExistingAccounts.id | ForEach-Object {
            [PSCustomObject]@{
                name        = $_.displayName
                description = $_.defaultDomainName
                id          = $_.defaultDomainName
            }
        } | ConvertTo-Json -Depth 10
        if ($NewAccounts) { Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/accounts' -Method POST -Headers $GradientToken -Body $NewAccounts -ContentType 'application/json' }
        #setting the integration to active
        $ExistingIntegrations = (Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization' -Method GET -Headers $GradientToken)
        if ($ExistingIntegrations.Status -ne 'active') {
            $ActivateRequest = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/status/active' -Method PATCH -Headers $GradientToken
        }
    } catch {
        Write-LogMessage -API $APIName -message "Failed to create tenants in Gradient API. Error: $($_.Exception.Message)" -Sev 'Error' -tenant 'GradientAPI'
    }

    $ConvertTable = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv

    # Licence counts come from the reporting DB (LicenseOverview), which already drops licences
    # excluded everywhere, rather than a live subscribedSkus call per tenant.
    foreach ($Tenant in $Tenants) {
        $TenantName = $Tenant.defaultDomainName
        $Licenses = @(New-CIPPDbRequest -TenantFilter $TenantName -Type 'LicenseOverview' -Fields 'skuId', 'License', 'TotalLicenses' | Where-Object { $_.skuId })
        if ($Licenses.Count -eq 0) {
            Write-LogMessage -API $APIName -message 'No cached licence data for this tenant, skipped. The licence cache fills on the next CIPP data collection.' -Sev 'Warning' -tenant $TenantName
            continue
        }
        foreach ($sku in $Licenses) {
            try {
                $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuId }).'Product_Display_Name' | Select-Object -Last 1
                if (!$PrettyName) { $PrettyName = $sku.License }
                #Check if serviceID exists by SKUID in gradient
                $ExistingService = (Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api' -Method GET -Headers $GradientToken).data.skus | Where-Object name -EQ $PrettyName
                if (!$ExistingService) {
                    #Create service
                    $ServiceBody = [PSCustomObject]@{
                        name        = $PrettyName
                        description = $PrettyName
                        category    = 'infrastructure'
                        subcategory = 'hosted email'
                    } | ConvertTo-Json -Depth 10
                    $ExistingService = (Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/service' -Method POST -Headers $GradientToken -Body $ServiceBody -ContentType 'application/json').skus | Where-Object name -EQ $PrettyName
                }
                #Post the purchased licence count to the service
                $ServiceBody = [PSCustomObject]@{
                    accountId = $TenantName
                    unitCount = [int]$sku.TotalLicenses
                } | ConvertTo-Json -Depth 10
                $null = Invoke-RestMethod -Uri "https://app.usegradient.com/api/vendor-api/service/$($ExistingService.id)/count" -Method POST -Headers $GradientToken -Body $ServiceBody -ContentType 'application/json'
            } catch {
                Write-LogMessage -API $APIName -message "Failed to sync licence '$PrettyName' to Gradient. Error: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantName
            }
        }
    }

}
