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
    Param([string]$TenantFilter)
    $DomainTable = Get-CIPPTable -Table 'Domains'

    # Get all the things

    if ($TenantFilter -ne 'AllTenants' -and ![string]::IsNullOrEmpty($TenantFilter)) {
        $DomainTable.Filter = "TenantGUID eq '{0}'" -f $TenantFilter
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
    return $Results
}