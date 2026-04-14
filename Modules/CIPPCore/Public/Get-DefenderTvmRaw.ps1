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

    try {
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
        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Error on page $page`: $($_.Exception.Message)" -Sev 'Error'
        throw
    }
}
