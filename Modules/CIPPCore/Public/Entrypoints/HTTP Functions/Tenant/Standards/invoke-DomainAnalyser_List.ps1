
using namespace System.Net

function Invoke-DomainAnalyser_List {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.DomainAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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


    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }
}
