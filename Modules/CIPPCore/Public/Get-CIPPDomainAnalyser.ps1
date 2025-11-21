function Get-CIPPDomainAnalyser {
    <#
    .SYNOPSIS
    Domain Analyser list

    .DESCRIPTION
    This function returns a list of domain analyser results for the selected tenant filter

    .PARAMETER TenantFilter
    Tenant to filter by, enter AllTenants to get all results

    .EXAMPLE
    Get-CIPPDomainAnalyser -TenantFilter 'AllTenants'
    #>
    [CmdletBinding()]
    param([string]$TenantFilter)
    $DomainTable = Get-CIPPTable -Table 'Domains'

    # Get all the things
    #Transform the tenantFilter to the GUID.
    if ($TenantFilter -ne 'AllTenants' -and ![string]::IsNullOrEmpty($TenantFilter)) {
        $TenantFilter = (Get-Tenants -TenantFilter $tenantFilter).customerId
        $DomainTable.Filter = "TenantGUID eq '{0}'" -f $TenantFilter
    } else {
        $Tenants = Get-Tenants -IncludeErrors
    }
    $Domains = Get-CIPPAzDataTableEntity @DomainTable | Where-Object { $_.TenantGUID -in $Tenants.customerId -or $TenantFilter -eq $_.TenantGUID }
    try {
        # Extract json from table results
        $Results = foreach ($DomainAnalyserResult in ($Domains).DomainAnalyser) {
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
    return $Results
}
