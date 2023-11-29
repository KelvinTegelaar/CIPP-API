function New-GradientServiceSyncRun {
    [CmdletBinding()]
    param (
        
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Gradient
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
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create tenants in Gradient API. Error: $($_.Exception.Message)" -Sev 'Error' -tenant 'GradientAPI'
    }


    Set-Location (Get-Item $PSScriptRoot).Parent.FullName
    $ConvertTable = Import-Csv Conversiontable.csv
    $Table = Get-CIPPTable -TableName cachelicenses
    $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
    $ExcludedSkuList = Get-CIPPAzDataTableEntity @LicenseTable

    $RawGraphRequest = $Tenants | ForEach-Object -Parallel { 
        $domainName = $_.defaultDomainName
        Import-Module '.\GraphHelper.psm1'
        Import-Module '.\Modules\AzBobbyTables'
        Import-Module '.\Modules\CIPPCore'
        Write-Host "Doing $domainName"
        try {
            $Licrequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $_.defaultDomainName -ErrorAction Stop
            [PSCustomObject]@{
                Tenant   = $domainName
                Licenses = $Licrequest
            } 
        } catch {
            [PSCustomObject]@{
                Tenant   = $domainName
                Licenses = @{ 
                    skuid         = "Could not connect to client: $($_.Exception.Message)"
                    skuPartNumber = 'Could not connect to client'
                    consumedUnits = 0 
                    prepaidUnits  = { Enabled = 0 }
                }
            } 
        }
    }
    $LicenseTable = foreach ($singlereq in $RawGraphRequest) {
        $skuid = $singlereq.Licenses
        foreach ($sku in $skuid) {
            try {
                if ($sku.skuId -eq 'Could not connect to client') { continue }
                $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
                if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                #Check if serviceID exists by SKUID in gradient
                $ExistingService = (Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api' -Method GET -Headers $GradientToken).data.skus | Where-Object name -EQ $PrettyName
                Write-Host "New service: $($ExistingService.name) ID: $($ExistingService.id)"               
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
                #Post the CountAvailable to the service
                $ServiceBody = [PSCustomObject]@{
                    accountId = $singlereq.Tenant
                    unitCount = $sku.prepaidUnits.enabled
                } | ConvertTo-Json -Depth 10
                $Results = Invoke-RestMethod -Uri "https://app.usegradient.com/api/vendor-api/service/$($ExistingService.id)/count" -Method POST -Headers $GradientToken -Body $ServiceBody -ContentType 'application/json'
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create license in Gradient API. Error: $($_). $results" -Sev 'Error' -tenant $singlereq.tenant

            }
        }
    }

}