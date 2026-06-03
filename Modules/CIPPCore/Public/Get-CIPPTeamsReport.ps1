function Get-CIPPTeamsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Teams'
            $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPTeamsReport -TenantFilter $Tenant
                    foreach ($Result in $TenantResults) {
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'TeamsReport' -tenant $Tenant -message "Failed to get report: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults | Sort-Object -Property displayName
        }

        $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Teams' | Where-Object { $_.RowKey -notlike '*-Count' }
        if (-not $Items) {
            throw "No cached Teams data found for $TenantFilter. Run a cache sync first."
        }

        $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $Items) {
            $Team = $Item.Data | ConvertFrom-Json -Depth 20
            $Team | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            $Results.Add($Team)
        }

        return @($Results | Sort-Object -Property displayName)
    } catch {
        Write-LogMessage -API 'TeamsReport' -tenant $TenantFilter -message "Failed to generate Teams report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
