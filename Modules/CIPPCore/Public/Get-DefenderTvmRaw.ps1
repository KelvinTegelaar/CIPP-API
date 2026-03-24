function Get-DefenderTvmRaw {
    <#
    .SYNOPSIS
        Fetch Defender TVM SoftwareVulnerabilitiesByMachine with paging.
    .PARAMETER TenantId
        Microsoft Entra tenant id to query.
    .PARAMETER MaxPages
        Optional page cap (0 = no cap).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [int]$MaxPages = 0
    )

    $scope = 'https://api.securitycenter.microsoft.com/.default'
    $uri   = 'https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesByMachine'
    $all   = New-Object System.Collections.Generic.List[object]
    $page  = 0

    Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message 'Fetching SoftwareVulnerabilitiesByMachine' -Sev 'Debug'

    try {
        do {
            Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Fetching page $($page + 1) from: $uri" -Sev 'Debug'

            $resp = New-GraphGetRequest -tenantid $TenantId -uri $uri -scope $scope

            if ($resp -is [System.Collections.IDictionary]) {
                if ($resp.ContainsKey('value')) {
                    $rows     = $resp.value
                    $nextLink = $resp.'@odata.nextLink'

                    Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): $($rows.Count) records. NextLink: $($null -ne $nextLink)" -Sev 'Info'

                    if ($rows) { $all.AddRange($rows) }
                    $uri = $nextLink
                }
                else {
                    $all.Add($resp)
                    $uri = $null
                }
            }
            elseif ($resp -is [System.Collections.IEnumerable] -and $resp -isnot [string]) {
                $all.AddRange($resp)
                $uri = $null
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): $($resp.Count) records (array)" -Sev 'Info'
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

        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Fetch complete. Pages: $page, Records: $($all.Count)" -Sev 'Info'
        return $all
    }
    catch {
        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Error on page $page`: $($_.Exception.Message)" -Sev 'Error'
        throw
    }
}
