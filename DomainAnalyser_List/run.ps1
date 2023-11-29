using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$DomainTable = Get-CIPPTable -Table 'Domains'

# Get all the things

if ($Request.Query.tenantFilter -ne 'AllTenants') {
    $DomainTable.Filter = "TenantId eq '{0}'" -f $Request.Query.tenantFilter
}

try {
    # Extract json from table results
    $Results = foreach ($DomainAnalyserResult in (Get-CIPPAzDataTableEntity @DomainTable).DomainAnalyser) {
        try { 
            if (![string]::IsNullOrEmpty($DomainAnalyserResult)) {
                $Object = $DomainAnalyserResult | ConvertFrom-Json

                if (($Request.Query.tenantFilter -eq 'AllTenants' -and $Object.Tenant -notin $Skiplist.Name) -or $Request.Query.tenantFilter -ne 'AllTenants') {
                    $Object.GUID = $Object.GUID -replace '[^a-zA-Z-]', ''
                    $Object
                }
            }
        } catch {}
    }
} catch {
    $Results = @()
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    })