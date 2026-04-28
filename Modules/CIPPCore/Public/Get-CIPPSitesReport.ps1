function Get-CIPPSitesReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$Type = 'SharePointSiteUsage',

        [string]$URLOnly
    )

    try {
        $DbType = "Sites$Type"

        if ($TenantFilter -eq 'AllTenants') {
            $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type $DbType
            $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPSitesReport -TenantFilter $Tenant -Type $Type -URLOnly $URLOnly
                    foreach ($Result in $TenantResults) {
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'SitesReport' -tenant $Tenant -message "Failed to get report: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults | Sort-Object -Property displayName
        }

        $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType | Where-Object { $_.RowKey -notlike '*-Count' }
        if (-not $Items) {
            throw "No cached sites data found for $TenantFilter. Run a cache sync first."
        }

        $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $Items) {
            $Site = $Item.Data | ConvertFrom-Json -Depth 20
            $Site | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            $Results.Add($Site)
        }

        if ($URLOnly -eq 'true') {
            return @($Results | Where-Object { $null -ne $_.webUrl } | Sort-Object -Property displayName)
        }

        return @($Results | Sort-Object -Property displayName)
    } catch {
        Write-LogMessage -API 'SitesReport' -tenant $TenantFilter -message "Failed to generate sites report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
