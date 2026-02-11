function Get-CIPPMFAStateReport {
    <#
    .SYNOPSIS
        Generates an MFA state report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves MFA state data for a tenant from the reporting database

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .EXAMPLE
        Get-CIPPMFAStateReport -TenantFilter 'contoso.onmicrosoft.com'
        Gets MFA state for all users in the tenant
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {

        # Handle AllTenants
        if ($TenantFilter -eq 'AllTenants') {
            # Get all tenants that have MFA data
            $AllMFAItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MFAState'
            $Tenants = @($AllMFAItems | Where-Object { $_.RowKey -ne 'MFAState-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPMFAStateReport -TenantFilter $Tenant
                    foreach ($Result in $TenantResults) {
                        # Add Tenant property to each result
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'MFAStateReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Get MFA state from reporting DB
        $MFAItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MFAState' | Where-Object { $_.RowKey -ne 'MFAState-Count' }
        if (-not $MFAItems) {
            throw 'No MFA state data found in reporting database. Sync the report data first.'
        }
        # Get the most recent cache timestamp
        $CacheTimestamp = ($MFAItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        # Parse MFA state data
        $AllMFAState = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $MFAItems | Where-Object { $_.RowKey -ne 'MFAState-Count' }) {
            $MFAUser = $Item.Data | ConvertFrom-Json

            # Parse nested JSON properties if they're strings
            if ($MFAUser.CAPolicies -is [string]) {
                $MFAUser.CAPolicies = try { $MFAUser.CAPolicies | ConvertFrom-Json } catch { $MFAUser.CAPolicies }
            }
            if ($MFAUser.MFAMethods -is [string]) {
                $MFAUser.MFAMethods = try { $MFAUser.MFAMethods | ConvertFrom-Json } catch { $MFAUser.MFAMethods }
            }

            # Add cache timestamp
            $MFAUser | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force

            $AllMFAState.Add($MFAUser)
        }

        return $AllMFAState | Sort-Object -Property DisplayName

    } catch {
        Write-LogMessage -API 'MFAStateReport' -tenant $TenantFilter -message "Failed to generate MFA state report: $($_.Exception.Message)" -sev Error
        throw
    }
}
