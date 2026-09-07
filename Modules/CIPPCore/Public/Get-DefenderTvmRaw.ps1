function Get-DefenderTvmRaw {
    <#
    .SYNOPSIS
        Fetch Defender TVM SoftwareVulnerabilitiesByMachine with paging.
    .PARAMETER TenantId
        Microsoft Entra tenant id to query.
    .PARAMETER MaxPages
        Optional page cap (0 = no cap).
    .PARAMETER Stream
        Emit records straight to the pipeline instead of buffering the whole tenant
        dataset into a list. Peak memory becomes one page rather than every record,
        so use this when the consumer folds records as they arrive rather than
        indexing the result (see Set-CIPPDBCacheDefenderCVEs). The buffered default
        is unchanged. Trade-off: on a mid-pagination failure, records already emitted
        have flowed downstream before the throw.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [int]$MaxPages = 0,
        [switch]$Stream
    )

    $scope = 'https://api.securitycenter.microsoft.com/.default'
    $uri   = 'https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesByMachine'
    $all   = New-Object System.Collections.Generic.List[object]
    $page  = 0

    try {
        if ($Stream) {
            Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message 'Streaming Defender TVM fetch' -Sev 'Debug'
            New-GraphGetRequest -tenantid $TenantId -uri $uri -scope $scope -Stream
            return
        }

        # New-GraphGetRequest already follows @odata.nextLink internally and returns the
        # flattened .value rows for every page, so this loop only ever runs once and
        # $MaxPages never takes effect. Both in-repo callers (get-DefenderCVEs and
        # Set-CIPPDBCacheDefenderCVEs) now pass -Stream, so this buffered path is kept only
        # for ad-hoc use - it holds the whole tenant dataset, so don't put it back on a hot
        # path.
        do {
            Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Fetching page $($page + 1)" -Sev 'Debug'

            $resp = New-GraphGetRequest -tenantid $TenantId -uri $uri -scope $scope

            if ($resp -is [System.Collections.IDictionary]) {
                if ($resp.ContainsKey('value')) {
                    $rows     = $resp.value
                    $nextLink = $resp.'@odata.nextLink'
                    if ($rows) { $all.AddRange($rows) }
                    $uri = $nextLink
                    Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): $($rows.Count) records" -Sev 'Debug'
                }
                else {
                    $all.Add($resp)
                    $uri = $null
                }
            }
            elseif ($resp -is [System.Collections.IEnumerable] -and $resp -isnot [string]) {
                $all.AddRange($resp)
                $uri = $null
            }
            else {
                $all.Add($resp)
                $uri = $null
            }

            $page++

            if ($page -gt 100) {
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Reached 100 page safety limit — stopping" -Sev 'Warning'
                break
            }

        } while ($uri -and ($MaxPages -eq 0 -or $page -lt $MaxPages))

        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Defender TVM fetch complete: $($all.Count) records across $page page(s)" -Sev 'Info'
        return $all
    }
    catch {
        $Sev = if (Test-CIPPCacheCapabilityError -Message $_.Exception.Message) { 'Debug' } else { 'Error' }
        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Error on page $page`: $($_.Exception.Message)" -Sev $Sev
        throw
    }
}
