function Get-CIPPMDEOnboardingReport {
    <#
    .SYNOPSIS
        Generates an MDE onboarding status report from the CIPP Reporting database
    .PARAMETER TenantFilter
        The tenant to generate the report for
    #>
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
            $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MDEOnboarding' -ByTenant

            if ($ItemsByTenant.Count -eq 0) {
                throw 'No MDE onboarding data found in reporting database for any tenant. Sync the report data first.'
            }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in @($ItemsByTenant.Keys)) {
                # Hand each tenant its rows and drop them here so they can be freed once processed
                $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
                try {
                    $TenantResults = Get-CIPPMDEOnboardingReport -TenantFilter $Tenant -DbItems @{ MDEOnboarding = $TenantItems }
                    foreach ($Result in $TenantResults) {
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'MDEOnboardingReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        $Items = $(if ($DbItems) { $DbItems['MDEOnboarding'] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MDEOnboarding' }) | Where-Object { $_.RowKey -ne 'MDEOnboarding-Count' }
        if (-not $Items) {
            throw 'No MDE onboarding data found in reporting database. Sync the report data first.'
        }

        $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $Items) {
            $ParsedData = $Item.Data | ConvertFrom-Json
            $ParsedData | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            $AllResults.Add($ParsedData)
        }

        return $AllResults
    } catch {
        Write-LogMessage -API 'MDEOnboardingReport' -tenant $TenantFilter -message "Failed to generate MDE onboarding report: $($_.Exception.Message)" -sev Error
        throw
    }
}
