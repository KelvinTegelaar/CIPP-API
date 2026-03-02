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
            Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Fetching page $($page + 1)..." -Sev 'Debug'
            
            $resp = New-GraphGetRequest -tenantid $TenantId -uri $uri -scope $scope
            
            if ($resp -is [System.Collections.IDictionary] -and $resp.ContainsKey('value')) {
                $rows = $resp.value
                $uri  = $resp.'@odata.nextLink'
                
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): Retrieved $($rows.Count) records. NextLink present: $($null -ne $uri)" -Sev 'Info'
                
                if ($uri) {
                    Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "NextLink: $uri" -Sev 'Debug'
                }
            } else {
                $rows = $resp
                $uri  = $null
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Page $($page + 1): Retrieved $($rows.Count) records (no pagination wrapper)" -Sev 'Info'
            }
            
            if ($rows) { 
                $all.AddRange($rows) 
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Total records so far: $($all.Count)" -Sev 'Debug'
            }
            
            $page++
            
            # Safety check to prevent infinite loops
            if ($page -gt 100) {
                Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "WARNING: Reached 100 pages, stopping to prevent infinite loop" -Sev 'Warning'
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
