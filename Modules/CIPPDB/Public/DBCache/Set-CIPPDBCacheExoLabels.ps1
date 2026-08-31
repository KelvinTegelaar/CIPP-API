function Set-CIPPDBCacheExoLabels {
    <#
    .SYNOPSIS
        Caches Purview sensitivity labels from the Security & Compliance endpoint (requires Purview/AIP license)

    .DESCRIPTION
        Calls Get-Label against the Security & Compliance endpoint and writes the results into the
        CIPP database under Type 'ExoLabels'. Selects Name and DisplayName - the fields the
        SensitivityLabelTemplate standard matches deployed labels on. Distinct from the
        'SensitivityLabels' type, which caches the Graph informationProtection view.

    .PARAMETER TenantFilter
        The tenant to cache labels for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'ExoLabelsCache' -TenantFilter $TenantFilter -Preset Compliance -SkipLog

        if ($LicenseCheck -eq $false) {
            # Warning, not Debug: Test-CIPPStandardLicense also returns $false when the capability
            # lookup itself errors, so a wrong gate on a tenant that DOES have Purview must be
            # visible in the logs rather than silently parking the standard at No Data.
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Purview/AIP capability check returned '$LicenseCheck' (requires one of RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2) - skipping compliance labels and recording an authoritative empty set" -sev Warning
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoLabels' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching compliance labels' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $Labels = New-ExoRequest -TenantId $Tenant.customerId -cmdlet 'Get-Label' -Compliance -Select 'Name,DisplayName'

        if ($Labels) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoLabels' -Data @($Labels) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Labels).Count) compliance labels" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoLabels' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 compliance labels (none found)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache compliance labels: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
