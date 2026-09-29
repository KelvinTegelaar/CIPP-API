function Get-CIPPIntuneReusableSettingsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    if ($TenantFilter -eq 'AllTenants') {
        $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'IntuneReusableSettings' -ByTenant

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in @($ItemsByTenant.Keys)) {
            # Hand each tenant its rows and drop them here so they can be freed once processed
            $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
            try {
                $TenantResults = Get-CIPPIntuneReusableSettingsReport -TenantFilter $Tenant -DbItems @{ IntuneReusableSettings = $TenantItems }
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

    $Items = $(if ($DbItems) { $DbItems['IntuneReusableSettings'] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' }) | Where-Object { $_.RowKey -notlike '*-Count' }
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

        $Setting | Add-Member -NotePropertyMembers ([ordered]@{
                RawJSON        = $rawJson
                CacheTimestamp = $CacheTimestamp
            }) -Force
        $Results.Add($Setting)
    }

    return $Results
}
