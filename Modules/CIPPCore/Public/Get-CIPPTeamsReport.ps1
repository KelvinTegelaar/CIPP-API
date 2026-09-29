function Get-CIPPTeamsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Teams' -ByTenant

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in @($ItemsByTenant.Keys)) {
                # Hand each tenant its rows and drop them here so they can be freed once processed
                $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
                try {
                    $TenantResults = Get-CIPPTeamsReport -TenantFilter $Tenant -DbItems @{ Teams = $TenantItems }
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

        $Items = $(if ($DbItems) { $DbItems['Teams'] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Teams' }) | Where-Object { $_.RowKey -notlike '*-Count' }
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
