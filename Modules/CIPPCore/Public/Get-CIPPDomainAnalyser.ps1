function Get-CIPPDomainAnalyser {
    [CmdletBinding()]
    Param($TenantFilter)
    $DomainTable = Get-CIPPTable -Table 'Domains'

    # Get all the things

    if ($TenantFilter -ne 'AllTenants') {
        $DomainTable.Filter = "TenantId eq '{0}'" -f $TenantFilter
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