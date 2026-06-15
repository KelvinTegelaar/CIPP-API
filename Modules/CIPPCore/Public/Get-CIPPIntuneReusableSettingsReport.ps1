function Get-CIPPIntuneReusableSettingsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneReusableSettings'
        $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPIntuneReusableSettingsReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'IntuneReusableSettingsReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $Items) {
        throw "No reusable settings data found for $TenantFilter. Run a cache sync first."
    }

    $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Item in $Items) {
        $Setting = try { $Item.Data | ConvertFrom-Json -Depth 50 -ErrorAction Stop } catch { continue }
        if ($null -eq $Setting) { continue }

        $rawJson = $null
        try {
            $rawJson = $Setting | ConvertTo-Json -Depth 50 -Compress -ErrorAction Stop
        } catch {
            $rawJson = $null
        }

        $Setting | Add-Member -NotePropertyName 'RawJSON' -NotePropertyValue $rawJson -Force
        $Setting | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
        $Results.Add($Setting)
    }

    return $Results
}
