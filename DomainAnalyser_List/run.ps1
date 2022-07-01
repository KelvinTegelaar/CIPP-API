using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$DomainTable = Get-CIPPTable -Table 'Domains'

# Get all the things

# Convert file json results to table results
if (Test-Path .\Cache_DomainAnalyser) {
    $UnfilteredResults = Get-ChildItem '.\Cache_DomainAnalyser\*.json' | ForEach-Object { Get-Content $_.FullName | Out-String }
    
    foreach ($Result in $UnfilteredResults) { 
        $Object = $Result | ConvertFrom-Json

        $MigratePartitionKey = @{
            Table        = $DomainTable
            PartitionKey = $Tenant.Tenant
            RowKey       = $Tenant.Domain
        }

        $OldDomain = Get-AzTableRow @MigratePartitionKey

        if ($OldDomain) {
            $OldDomain | Remove-AzTableRow -Table $DomainTable
        }

        $ExistingDomain = @{
            Table        = $DomainTable
            rowKey       = $Object.Domain
            partitionKey = 'TenantDomains'
        }

        $Domain = Get-AzTableRow @ExistingDomain

        if (!$Domain) {
            Write-Host 'Adding domain from cache file'
            $DomainObject = @{
                Table        = $DomainTable
                rowKey       = $Object.Domain
                partitionKey = 'TenantDomains'
                property     = @{
                    DomainAnalyser = $Result
                    TenantId       = $Object.Tenant
                    TenantDetails  = ''
                    DkimSelectors  = ''
                    MailProviders  = ''
                }
            }

            if ($OldDomain) {
                $DomainObject.property.DkimSelectors = $OldDomain.DkimSelectors
                $DomainObject.property.MailProviders = $OldDomain.MailProviders
            }

            Add-AzTableRow @DomainObject | Out-Null
        }
        else {
            Write-Host 'Updating domain from cache file'
            $Domain.DomainAnalyser = $Result
            if ($OldDomain) {
                $Domain.DkimSelectors = $OldDomain.DkimSelectors
                $Domain.MailProviders = $OldDomain.MailProviders
            }
            $Domain | Update-AzTableRow -Table $DomainTable | Out-Null
        }
        Remove-Item -Path ".\Cache_DomainAnalyser\$($Object.Domain).DomainAnalysis.json" | Out-Null
    }
}

# Need to apply exclusion logic
$Skiplist = Get-Content 'ExcludedTenants' | ConvertFrom-Csv -Delimiter '|' -Header 'Name', 'User', 'Date'

$DomainList = @{
    Table        = $DomainTable
    SelectColumn = @('partitionKey', 'DomainAnalyser', 'TenantId')
}

if ($Request.Query.tenantFilter -ne 'AllTenants') {
    $DomainList.columnName = 'TenantId' 
    $DomainList.operator = 'Equal'
    $DomainList.value = $Request.Query.tenantFilter
}

try {
    # Extract json from table results
    $Results = foreach ($DomainAnalyserResult in (Get-AzTableRow @DomainList).DomainAnalyser) {
        try { 
            if (![string]::IsNullOrEmpty($DomainAnalyserResult)) {
                $Object = $DomainAnalyserResult | ConvertFrom-Json

                if (($Request.Query.tenantFilter -eq 'AllTenants' -and $Object.Tenant -notin $Skiplist.Name) -or $Request.Query.tenantFilter -ne 'AllTenants') {
                    $Object.GUID = $Object.GUID -replace '[^a-zA-Z-]', ''
                    $Object
                }
            }
        }
        catch {}
    }
}
catch {
    $Results = @()
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    })