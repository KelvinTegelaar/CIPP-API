
using namespace System.Net

Function Invoke-DomainAnalyser_List {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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
                    $Object = $DomainAnalyserResult | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $Object
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
}