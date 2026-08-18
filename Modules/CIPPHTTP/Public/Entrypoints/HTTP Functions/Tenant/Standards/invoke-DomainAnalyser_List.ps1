
using namespace System.Net

Function Invoke-DomainAnalyser_List {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.DomainAnalyser.Read
    .DESCRIPTION
        Returns the cached Domain Analyser results: the DNS health of each tenant's domains, covering MX, SPF, DKIM, DMARC and DNSSEC. Populated by a scheduled job, so this reads the last run rather than resolving DNS live. tenantFilter=AllTenants returns every tenant's domains.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $DomainTable = Get-CIPPTable -Table 'Domains'

    # Get all the things

    if ($Request.Query.tenantFilter -ne 'AllTenants') {
        $DomainTable.Filter = "TenantId eq '{0}'" -f $Request.Query.tenantFilter
    }

    try {
        # AnyTenant skips the framework's per-tenant check, so scoping is enforced here: narrow the
        # rows to the caller's allowed tenants before extracting results. Rows carry the tenant as
        # TenantGUID (customerId) and TenantId (defaultDomainName), matching Get-CIPPDomainAnalyser.
        $DomainRows = Get-CIPPAzDataTableEntity @DomainTable | Select-CippAllowedTenantData -TenantProperty 'TenantGUID', 'TenantId'
        # Extract json from table results
        $Results = foreach ($DomainAnalyserResult in $DomainRows.DomainAnalyser) {
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


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })
}
