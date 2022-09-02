using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$DomainTable = Get-CIPPTable -Table 'Domains'

# Get all the things

# Convert file json results to table results
if (Test-Path .\Cache_DomainAnalyser) {
    $UnfilteredResults = Get-ChildItem '.\Cache_DomainAnalyser\*.json' | ForEach-Object { Get-Content $_.FullName | Out-String }
    
    foreach ($Result in $UnfilteredResults) { 
        $Object = $Result | ConvertFrom-Json


        $Filter = "PartitionKey eq '{0}' and RowKey eq '{1}'" -f $Tenant.Tenant, $Tenant.Domain
        $OldDomain = Get-AzDataTableEntity @DomainTale -Filter $Filter

        if ($OldDomain) {
            Remove-AzDataTableEntity @DomainTable -Entity $OldDomain
        }



        $Filter = "PartitionKey eq 'TenantDomains' and RowKey eq '{1}'" -f $Tenant.Domain
        $Domain = Get-AzDataTableEntity @DomainTable -Filter $Filter 

        if (!$Domain) {
            Write-Host 'Adding domain from cache file'

            $DomainObject = @{
                DomainAnalyser = ''
                TenantDetails  = $TenantDetails
                TenantId       = $Tenant.Tenant
                DkimSelectors  = ''
                MailProviders  = ''
                rowKey         = $Tenant.Domain
                partitionKey   = 'TenantDomains'
            }

            if ($OldDomain) {
                $DomainObject.DkimSelectors = $OldDomain.DkimSelectors
                $DomainObject.MailProviders = $OldDomain.MailProviders
            }

            Add-AzDataTableEntity @DomainTable -Entity $DomainObject | Out-Null
        }
        else {
            Write-Host 'Updating domain from cache file'
            $Domain.DomainAnalyser = $Result
            if ($OldDomain) {
                $Domain.DkimSelectors = $OldDomain.DkimSelectors
                $Domain.MailProviders = $OldDomain.MailProviders
            }
            Update-AzDataTableEntity @DomainTable -Entity $Domain | Out-Null
        }
        Remove-Item -Path ".\Cache_DomainAnalyser\$($Object.Domain).DomainAnalysis.json" | Out-Null
    }
}



if ($Request.Query.tenantFilter -ne 'AllTenants') {

    $DomainTable.Filter = "TenantId eq '{0}'" -f $Request.Query.tenantFilter
}

try {
    # Extract json from table results
    $Results = foreach ($DomainAnalyserResult in (Get-AzDataTableEntity @DomainTable).DomainAnalyser) {
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