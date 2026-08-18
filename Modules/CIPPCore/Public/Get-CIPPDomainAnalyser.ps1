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

    if (-not $script:CIPPDomainAnalyserCache) {
        $script:CIPPDomainAnalyserCache = @{}
    }
    # The in-worker results cache is keyed by tenant filter alone, and a worker serves many
    # callers in turn: results computed under one caller's tenant scope must never be replayed
    # to a caller with a different scope. Tenant-restricted requests therefore skip the cache
    # entirely, in both directions; the unrestricted majority (admins, background alert and
    # test runs) keeps the caching benefit.
    $ScopeRestricted = $null -ne (Get-CippRequestContext).AllowedTenants
    $CacheKey = if ([string]::IsNullOrEmpty($TenantFilter)) { 'AllTenants' } else { $TenantFilter }
    $CacheNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $ScopeRestricted) {
        $CachedEntry = $script:CIPPDomainAnalyserCache[$CacheKey]
        if ($CachedEntry -and ($CacheNow - $CachedEntry.Timestamp) -lt 300) {
            return $CachedEntry.Results
        }
    }

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
        # Extract json from table results and merge with DkimSelectors from the domain entity
        $Results = foreach ($Domain in $Domains) {
            try {
                if (![string]::IsNullOrEmpty($Domain.DomainAnalyser)) {
                    $Object = $Domain.DomainAnalyser | ConvertFrom-Json -ErrorAction SilentlyContinue
                    # Add DkimSelectors from the domain entity if available
                    if (![string]::IsNullOrEmpty($Domain.DkimSelectors)) {
                        $Selectors = $Domain.DkimSelectors | ConvertFrom-Json -ErrorAction SilentlyContinue
                        $Object | Add-Member -NotePropertyName 'DkimSelectors' -NotePropertyValue ($Selectors) -Force
                    }
                    $Object
                }
            } catch {}
        }
    } catch {
        $Results = @()
    }
    if (-not $ScopeRestricted) {
        $script:CIPPDomainAnalyserCache[$CacheKey] = @{ Results = $Results; Timestamp = $CacheNow }
    }
    return $Results
}
