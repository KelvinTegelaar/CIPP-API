function Set-CIPPDBCacheMoeraDmarc {
    <#
    .SYNOPSIS
        Caches DMARC state for MOERA (onmicrosoft.com) domains for a tenant

    .DESCRIPTION
        Resolves the tenant's MOERA domains (*.onmicrosoft.com, excluding *.mail.onmicrosoft.com)
        from Graph and reads each domain's live DMARC policy over DNS via the DNSHealth module,
        the same lookup Invoke-CIPPStandardAddDMARCToMOERA performs. A domain whose DNS query
        fails is skipped rather than cached as a false "no DMARC" negative; on a partial run the
        successful rows are appended without deleting previously cached rows for the failed domains.

    .PARAMETER TenantFilter
        The tenant to cache MOERA DMARC state for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching MOERA domain DMARC state' -sev Debug

        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter
        $MoeraDomains = @($Domains | Where-Object { $_.id -like '*.onmicrosoft.com' -and $_.id -notlike '*.mail.onmicrosoft.com' } | Select-Object -ExpandProperty id)

        $Results = [System.Collections.Generic.List[object]]::new()
        $FailedDomains = [System.Collections.Generic.List[string]]::new()

        foreach ($Domain in $MoeraDomains) {
            try {
                $DmarcPolicy = Read-DmarcPolicy -Domain $Domain
                $Results.Add([PSCustomObject]@{
                        id              = $Domain
                        domain          = $Domain
                        hasDmarc        = -not [string]::IsNullOrEmpty($DmarcPolicy.Record)
                        record          = $DmarcPolicy.Record
                        policy          = $DmarcPolicy.Policy
                        subdomainPolicy = $DmarcPolicy.SubdomainPolicy
                        percent         = $DmarcPolicy.Percent
                    })
            } catch {
                # A resolver failure is not evidence the record is missing - skip the domain
                # so the cache never holds a false negative for it.
                $FailedDomains.Add($Domain)
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to read DMARC policy for MOERA domain $($Domain): $($_.Exception.Message)" -sev Error
            }
        }

        if ($FailedDomains.Count -eq 0) {
            # Full authoritative run: write everything and allow cleanup of rows for
            # domains that no longer exist (including clearing on a genuinely empty set).
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MoeraDmarc' -Data $Results -AddCount -ClearOnEmpty
        } elseif ($Results.Count -gt 0) {
            # Partial run: append the successful rows only, so previously cached rows for
            # the failed domains are not deleted by the orphan cleanup.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MoeraDmarc' -Data $Results -AddCount -Append
        } else {
            throw "DMARC resolution failed for all $($FailedDomains.Count) MOERA domains: $($FailedDomains -join ', ')"
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached MOERA domain DMARC state successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache MOERA domain DMARC state: $($_.Exception.Message)" -sev Error
    }
}
