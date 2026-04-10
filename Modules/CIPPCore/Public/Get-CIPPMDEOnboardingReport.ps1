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
        [string]$TenantFilter
    )

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $AllItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MDEOnboarding'
            $Tenants = @($AllItems | Where-Object { $_.RowKey -ne 'MDEOnboarding-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPMDEOnboardingReport -TenantFilter $Tenant
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

        $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MDEOnboarding' | Where-Object { $_.RowKey -ne 'MDEOnboarding-Count' }
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
