function Set-CIPPDBCacheDomainAnalyser {
    <#
    .SYNOPSIS
        Caches Domain Analyser results for a tenant

    .DESCRIPTION
        Snapshots the Domain Analyser results already computed into the Domains table (SPF, MX,
        DMARC, DKIM, DNSSEC, enrollment CNAMEs and the health score per domain) into
        CippReportingDB, so custom tests and reports can read them via
        Get-CIPPTestData -Type 'DomainAnalyser'. No DNS work happens here - the nightly
        Start-DomainOrchestrator run produces the data before this cache pass; this function
        only copies it.

        A tenant with no analyser results is skipped without writing anything: an empty set
        usually means the Domain Analyser has not run for the tenant yet, which is not an
        authoritative "no domains" answer.

    .PARAMETER TenantFilter
        The tenant to cache Domain Analyser results for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Domain Analyser results' -sev Debug

        $Results = @(Get-CIPPDomainAnalyser -TenantFilter $TenantFilter)

        if ($Results.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No Domain Analyser results to cache - the Domain Analyser has not run for this tenant yet' -sev Debug
            return
        }

        # A stable id gives deterministic row keys (DomainAnalyser-<domain>) so reruns upsert in
        # place instead of inserting GUID-keyed rows and orphan-deleting the previous run's. The
        # records are copied first because Get-CIPPDomainAnalyser serves them from a shared
        # in-worker cache that other callers read.
        $Rows = @(foreach ($Result in $Results) {
                $Row = $Result.PSObject.Copy()
                $Row | Add-Member -NotePropertyName 'id' -NotePropertyValue $Result.Domain -Force
                $Row
            })

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DomainAnalyser' -Data $Rows -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Domain Analyser results successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Domain Analyser results: $($_.Exception.Message)" -sev Error
        throw
    }
}
