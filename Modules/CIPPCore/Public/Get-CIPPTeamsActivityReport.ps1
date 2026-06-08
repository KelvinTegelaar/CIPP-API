function Get-CIPPTeamsActivityReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$Type = 'TeamsUserActivityUser'
    )

    try {
        $DbType = "TeamsActivity$Type"

        if ($TenantFilter -eq 'AllTenants') {
            $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type $DbType
            $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPTeamsActivityReport -TenantFilter $Tenant -Type $Type
                    foreach ($Result in $TenantResults) {
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'TeamsActivityReport' -tenant $Tenant -message "Failed to get report: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults | Sort-Object -Property UPN
        }

        $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType | Where-Object { $_.RowKey -notlike '*-Count' }
        if (-not $Items) {
            throw "No cached Teams activity data found for $TenantFilter. Run a cache sync first."
        }

        $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $Items) {
            $Activity = $Item.Data | ConvertFrom-Json -Depth 20
            $Activity | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            $Results.Add($Activity)
        }

        return @($Results | Sort-Object -Property UPN)
    } catch {
        Write-LogMessage -API 'TeamsActivityReport' -tenant $TenantFilter -message "Failed to generate Teams activity report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
