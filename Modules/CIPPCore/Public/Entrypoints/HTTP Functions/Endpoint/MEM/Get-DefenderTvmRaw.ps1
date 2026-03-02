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
    $uri   = 'https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesByMachine?$top=999'
    $all   = New-Object System.Collections.Generic.List[object]
    $page  = 0

    Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message 'Fetching SoftwareVulnerabilitiesByMachine…' -Sev 'Debug'
    try {
        do {
            Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Fetching page $($page + 1) from: $uri" -Sev 'Debug'
            
            # Use -NoPagination to get raw response with nextLink
            $resp = New-GraphGetRequest -tenantid $TenantId -uri $uri -scope $scope -NoPagination $true
            
            # Handle response structure
            if ($resp -is [System.Collections.IDictionary]) {
                if ($resp.ContainsKey('value')) {
                    $rows = $resp.value
                    $nextLink = $resp.'@odata.nextLink'
                    
                    Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): Retrieved $($rows.Count) records. NextLink present: $($null -ne $nextLink)" -Sev 'Info'
                    
                    if ($rows) { $all.AddRange($rows) }
                    $uri = $nextLink
                } else {
                    # Dictionary but no 'value' key - treat as single result
                    $all.Add($resp)
                    $uri = $null
                    Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): Single record (dictionary)" -Sev 'Debug'
                }
            } elseif ($resp -is [System.Collections.IEnumerable] -and $resp -isnot [string]) {
                # It's an array - add all items
                $all.AddRange($resp)
                $uri = $null
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): Retrieved $($resp.Count) records (array, no nextLink)" -Sev 'Info'
            } else {
                # Single object
                $all.Add($resp)
                $uri = $null
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): Single record" -Sev 'Debug'
            }
            
            $page++
            
            # Safety check
            if ($page -gt 100) {
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "WARNING: Reached 100 pages, stopping" -Sev 'Warning'
                break
            }
            
        } while ($uri -and ($MaxPages -eq 0 -or $page -lt $MaxPages))

        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Fetch complete. Total pages: $page, Total records: $($all.Count)" -Sev 'Info'
        return $all
    }
    catch {
        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message ("Error on page $page : {0}" -f $_.Exception.Message) -Sev 'Error'
        throw
    }
}
